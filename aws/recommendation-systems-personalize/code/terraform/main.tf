# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  
  # Resource names with unique suffix
  bucket_name         = "${var.s3_bucket_name}-${local.resource_suffix}"
  dataset_group_name  = "${var.dataset_group_name}-${local.resource_suffix}"
  solution_name       = "${var.solution_name}-${local.resource_suffix}"
  campaign_name       = "${var.campaign_name}-${local.resource_suffix}"
  lambda_function_name = "${var.lambda_function_name}-${local.resource_suffix}"
  api_gateway_name    = "${var.api_gateway_name}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Purpose     = "real-time-recommendations"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 BUCKET FOR TRAINING DATA
# ============================================================================

# S3 bucket for storing training data
resource "aws_s3_bucket" "training_data" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Name = local.bucket_name
    Type = "training-data-storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "training_data" {
  bucket = aws_s3_bucket.training_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "training_data" {
  bucket = aws_s3_bucket.training_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "training_data" {
  count  = var.enable_s3_intelligent_tiering ? 1 : 0
  bucket = aws_s3_bucket.training_data.id
  
  rule {
    id     = "training_data_lifecycle"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Upload sample training data
resource "aws_s3_object" "sample_interactions" {
  bucket = aws_s3_bucket.training_data.id
  key    = "training-data/interactions.csv"
  
  content = <<-EOF
USER_ID,ITEM_ID,TIMESTAMP,EVENT_TYPE
user1,item101,1640995200,purchase
user1,item102,1640995260,view
user1,item103,1640995320,purchase
user2,item101,1640995380,view
user2,item104,1640995440,purchase
user2,item105,1640995500,view
user3,item102,1640995560,purchase
user3,item103,1640995620,view
user3,item106,1640995680,purchase
user4,item101,1640995740,view
user4,item107,1640995800,purchase
user5,item108,1640995860,view
user5,item109,1640995920,purchase
user6,item110,1640995980,view
user6,item111,1641000040,purchase
user7,item112,1641000100,view
user7,item113,1641000160,purchase
user8,item114,1641000220,view
user8,item115,1641000280,purchase
user9,item116,1641000340,view
user9,item117,1641000400,purchase
user10,item118,1641000460,view
user10,item119,1641000520,purchase
EOF
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name = "sample-interactions-data"
    Type = "training-data"
  })
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for Amazon Personalize
resource "aws_iam_role" "personalize_role" {
  name = "PersonalizeExecutionRole-${local.resource_suffix}"
  
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
    Name = "PersonalizeExecutionRole-${local.resource_suffix}"
    Type = "personalize-service-role"
  })
}

# IAM policy for Personalize to access S3
resource "aws_iam_policy" "personalize_s3_policy" {
  name        = "PersonalizeS3Policy-${local.resource_suffix}"
  description = "Policy for Amazon Personalize to access S3 training data"
  
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
          aws_s3_bucket.training_data.arn,
          "${aws_s3_bucket.training_data.arn}/*"
        ]
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policy to Personalize role
resource "aws_iam_role_policy_attachment" "personalize_s3_policy" {
  role       = aws_iam_role.personalize_role.name
  policy_arn = aws_iam_policy.personalize_s3_policy.arn
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "LambdaPersonalizeRole-${local.resource_suffix}"
  
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
    Name = "LambdaPersonalizeRole-${local.resource_suffix}"
    Type = "lambda-execution-role"
  })
}

# IAM policy for Lambda to access Personalize
resource "aws_iam_policy" "lambda_personalize_policy" {
  name        = "LambdaPersonalizePolicy-${local.resource_suffix}"
  description = "Policy for Lambda to access Amazon Personalize"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "personalize:GetRecommendations",
          "personalize:DescribeCampaign"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_personalize_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_personalize_policy.arn
}

# X-Ray tracing policy for Lambda (conditional)
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# AMAZON PERSONALIZE RESOURCES
# ============================================================================

# Note: Amazon Personalize resources are created here as placeholders
# In practice, these would be created through CLI or SDK after the infrastructure
# is deployed, as they require specific training data and time to complete

# Dataset group (placeholder - would be created via CLI)
# resource "aws_personalize_dataset_group" "recommendations" {
#   name = local.dataset_group_name
#   tags = local.common_tags
# }

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Lambda function source code
resource "local_file" "lambda_source" {
  content = <<-EOF
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Personalize client
personalize = boto3.client('personalize-runtime')

def lambda_handler(event, context):
    """
    Lambda handler for recommendation API requests
    """
    try:
        # Extract user ID from path parameters
        user_id = event['pathParameters']['userId']
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        num_results = int(query_params.get('numResults', 10))
        
        # Validate input
        if not user_id:
            return create_error_response(400, "User ID is required")
        
        if num_results < 1 or num_results > 100:
            return create_error_response(400, "numResults must be between 1 and 100")
        
        # Get campaign ARN from environment
        campaign_arn = os.environ.get('CAMPAIGN_ARN')
        if not campaign_arn:
            return create_error_response(500, "Campaign ARN not configured")
        
        # Get recommendations from Personalize
        logger.info(f"Getting recommendations for user: {user_id}")
        
        response = personalize.get_recommendations(
            campaignArn=campaign_arn,
            userId=user_id,
            numResults=num_results
        )
        
        # Format response
        recommendations = []
        for item in response['itemList']:
            recommendations.append({
                'itemId': item['itemId'],
                'score': float(item['score'])
            })
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps({
                'userId': user_id,
                'recommendations': recommendations,
                'totalCount': len(recommendations),
                'requestId': response['ResponseMetadata']['RequestId']
            })
        }
        
    except personalize.exceptions.InvalidInputException as e:
        logger.error(f"Invalid input: {str(e)}")
        return create_error_response(400, "Invalid input parameters")
    
    except personalize.exceptions.ResourceNotFoundException as e:
        logger.error(f"Resource not found: {str(e)}")
        return create_error_response(404, "Campaign or user not found")
    
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_error_response(500, "Internal server error")

def create_error_response(status_code, message):
    """Create standardized error response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'
        },
        'body': json.dumps({
            'error': message,
            'statusCode': status_code
        })
    }
EOF
  
  filename = "${path.module}/lambda_function.py"
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_source]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Type = "lambda-logs"
  })
}

# Lambda function
resource "aws_lambda_function" "recommendation_api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # Environment variables
  environment {
    variables = {
      CAMPAIGN_ARN = "arn:aws:personalize:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:campaign/${local.campaign_name}"
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "recommendation-api"
  })
}

# ============================================================================
# API GATEWAY
# ============================================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "recommendation_api" {
  name        = local.api_gateway_name
  description = "Real-time recommendation API powered by Amazon Personalize"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name = local.api_gateway_name
    Type = "recommendation-api"
  })
}

# API Gateway resource for /recommendations
resource "aws_api_gateway_resource" "recommendations" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  parent_id   = aws_api_gateway_rest_api.recommendation_api.root_resource_id
  path_part   = "recommendations"
}

# API Gateway resource for /recommendations/{userId}
resource "aws_api_gateway_resource" "user_recommendations" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  parent_id   = aws_api_gateway_resource.recommendations.id
  path_part   = "{userId}"
}

# API Gateway method for GET /recommendations/{userId}
resource "aws_api_gateway_method" "get_recommendations" {
  rest_api_id   = aws_api_gateway_rest_api.recommendation_api.id
  resource_id   = aws_api_gateway_resource.user_recommendations.id
  http_method   = "GET"
  authorization = "NONE"
  
  request_parameters = {
    "method.request.path.userId"              = true
    "method.request.querystring.numResults"   = false
  }
  
  request_validator_id = aws_api_gateway_request_validator.recommendations.id
}

# API Gateway request validator
resource "aws_api_gateway_request_validator" "recommendations" {
  name                        = "recommendation-validator"
  rest_api_id                = aws_api_gateway_rest_api.recommendation_api.id
  validate_request_body       = false
  validate_request_parameters = true
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  resource_id = aws_api_gateway_resource.user_recommendations.id
  http_method = aws_api_gateway_method.get_recommendations.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.recommendation_api.invoke_arn
}

# CORS OPTIONS method
resource "aws_api_gateway_method" "options_recommendations" {
  rest_api_id   = aws_api_gateway_rest_api.recommendation_api.id
  resource_id   = aws_api_gateway_resource.user_recommendations.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS OPTIONS integration
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  resource_id = aws_api_gateway_resource.user_recommendations.id
  http_method = aws_api_gateway_method.options_recommendations.http_method
  
  type = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS OPTIONS method response
resource "aws_api_gateway_method_response" "options_response" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  resource_id = aws_api_gateway_resource.user_recommendations.id
  http_method = aws_api_gateway_method.options_recommendations.http_method
  status_code = "200"
  
  response_headers = {
    "Access-Control-Allow-Headers" = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Origin"  = true
  }
}

# CORS OPTIONS integration response
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  resource_id = aws_api_gateway_resource.user_recommendations.id
  http_method = aws_api_gateway_method.options_recommendations.http_method
  status_code = aws_api_gateway_method_response.options_response.status_code
  
  response_headers = {
    "Access-Control-Allow-Headers" = "'${join(",", var.cors_allowed_headers)}'"
    "Access-Control-Allow-Methods" = "'${join(",", var.cors_allowed_methods)}'"
    "Access-Control-Allow-Origin"  = "'${join(",", var.cors_allowed_origins)}'"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recommendation_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.recommendation_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "recommendation_api" {
  depends_on = [
    aws_api_gateway_method.get_recommendations,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.options_recommendations,
    aws_api_gateway_integration.options_integration
  ]
  
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  stage_name  = var.api_gateway_stage_name
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "recommendation_api" {
  deployment_id = aws_api_gateway_deployment.recommendation_api.id
  rest_api_id   = aws_api_gateway_rest_api.recommendation_api.id
  stage_name    = var.api_gateway_stage_name
  
  # X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing
  
  tags = merge(local.common_tags, {
    Name = "${local.api_gateway_name}-${var.api_gateway_stage_name}"
    Type = "api-gateway-stage"
  })
}

# API Gateway method settings
resource "aws_api_gateway_method_settings" "recommendation_api" {
  rest_api_id = aws_api_gateway_rest_api.recommendation_api.id
  stage_name  = aws_api_gateway_stage.recommendation_api.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled        = true
    logging_level         = var.enable_api_gateway_logs ? "INFO" : "OFF"
    data_trace_enabled    = var.enable_api_gateway_logs
    throttling_rate_limit = var.api_gateway_throttle_rate_limit
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logs ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.recommendation_api.id}/${var.api_gateway_stage_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.recommendation_api.id}/${var.api_gateway_stage_name}"
    Type = "api-gateway-logs"
  })
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# SNS topic for alerts (if email is provided)
resource "aws_sns_topic" "alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  name  = "recommendation-api-alerts-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "recommendation-api-alerts-${local.resource_suffix}"
    Type = "alerting"
  })
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoint
}

# CloudWatch alarm for API Gateway 4xx errors
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "RecommendationAPI-4xxErrors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors 4xx errors in the recommendation API"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    ApiName = aws_api_gateway_rest_api.recommendation_api.name
  }
  
  tags = merge(local.common_tags, {
    Name = "RecommendationAPI-4xxErrors-${local.resource_suffix}"
    Type = "alarm"
  })
}

# CloudWatch alarm for API Gateway 5xx errors
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "RecommendationAPI-5xxErrors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors 5xx errors in the recommendation API"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    ApiName = aws_api_gateway_rest_api.recommendation_api.name
  }
  
  tags = merge(local.common_tags, {
    Name = "RecommendationAPI-5xxErrors-${local.resource_suffix}"
    Type = "alarm"
  })
}

# CloudWatch alarm for API Gateway latency
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "RecommendationAPI-Latency-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = var.latency_threshold
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    ApiName = aws_api_gateway_rest_api.recommendation_api.name
  }
  
  tags = merge(local.common_tags, {
    Name = "RecommendationAPI-Latency-${local.resource_suffix}"
    Type = "alarm"
  })
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "RecommendationLambda-Errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    FunctionName = aws_lambda_function.recommendation_api.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "RecommendationLambda-Errors-${local.resource_suffix}"
    Type = "alarm"
  })
}

# CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "RecommendationLambda-Duration-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout
  alarm_description   = "This metric monitors Lambda function duration"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []
  
  dimensions = {
    FunctionName = aws_lambda_function.recommendation_api.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "RecommendationLambda-Duration-${local.resource_suffix}"
    Type = "alarm"
  })
}