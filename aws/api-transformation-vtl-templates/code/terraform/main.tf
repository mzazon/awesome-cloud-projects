# Main Terraform configuration for request/response transformation with VTL templates

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  resource_suffix = random_id.suffix.hex
  api_name        = "${var.project_name}-${local.resource_suffix}"
  function_name   = "${var.lambda_function_name}-${local.resource_suffix}"
  bucket_name     = "${var.project_name}-data-store-${local.resource_suffix}"
  role_name       = "${var.project_name}-lambda-role-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.common_tags, {
    Environment = var.environment
    Region      = data.aws_region.current.name
    Suffix      = local.resource_suffix
  })
}

# ===== S3 BUCKET FOR DATA STORAGE =====

# S3 bucket for API data operations
resource "aws_s3_bucket" "api_data_store" {
  bucket        = local.bucket_name
  force_destroy = var.bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "Data store for API transformation operations"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "api_data_store" {
  bucket = aws_s3_bucket.api_data_store.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "api_data_store" {
  bucket = aws_s3_bucket.api_data_store.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "api_data_store" {
  bucket = aws_s3_bucket.api_data_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ===== IAM ROLES AND POLICIES =====

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = local.role_name

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
    Name        = local.role_name
    Description = "IAM role for Lambda function with S3 and CloudWatch access"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${local.role_name}-s3-policy"
  role = aws_iam_role.lambda_role.id

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
          aws_s3_bucket.api_data_store.arn,
          "${aws_s3_bucket.api_data_store.arn}/*"
        ]
      }
    ]
  })
}

# X-Ray tracing policy (conditional)
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ===== LAMBDA FUNCTION =====

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import uuid
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Log the transformed request for debugging
        print(f"Received event: {json.dumps(event)}")
        
        # Simulate processing based on event structure
        if 'user_data' in event:
            # Process user data from transformed request
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'user_id': event['user_data'].get('id'),
                'full_name': f"{event['user_data'].get('first_name', '')} {event['user_data'].get('last_name', '')}".strip(),
                'profile': {
                    'email': event['user_data'].get('email'),
                    'phone': event['user_data'].get('phone'),
                    'preferences': event['user_data'].get('preferences', {})
                },
                'status': 'processed',
                'metadata': {
                    'source': 'api_gateway_transformation',
                    'version': '2.0'
                }
            }
        else:
            # Handle generic data processing
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'input_data': event,
                'status': 'processed',
                'transformation_applied': True
            }
        
        return {
            'statusCode': 200,
            'body': response_data
        }
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal processing error',
                'message': str(e),
                'request_id': context.aws_request_id
            }
        }
EOF
    filename = "data-processor.py"
  }
}

# Lambda function
resource "aws_lambda_function" "data_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "data-processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  description = "Data processor with transformation support"
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  # Environment variables
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.api_data_store.bucket
      REGION      = data.aws_region.current.name
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.function_name
    Description = "Lambda function for processing transformed API requests"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.function_name}"
    Description = "Log group for Lambda function"
  })
}

# ===== API GATEWAY =====

# REST API Gateway
resource "aws_api_gateway_rest_api" "transformation_api" {
  name        = local.api_name
  description = var.api_description
  
  # Enable X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      tracing_enabled = true
    }
  }
  
  # API Gateway endpoint configuration
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name        = local.api_name
    Description = "REST API with VTL transformation capabilities"
  })
}

# ===== API GATEWAY MODELS =====

# Request model for user creation
resource "aws_api_gateway_model" "user_create_request" {
  rest_api_id  = aws_api_gateway_rest_api.transformation_api.id
  name         = "UserCreateRequest"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "User Creation Request"
    type      = "object"
    required  = ["firstName", "lastName", "email"]
    properties = {
      firstName = {
        type      = "string"
        minLength = 1
        maxLength = 50
        pattern   = "^[a-zA-Z\\s]+$"
      }
      lastName = {
        type      = "string"
        minLength = 1
        maxLength = 50
        pattern   = "^[a-zA-Z\\s]+$"
      }
      email = {
        type      = "string"
        format    = "email"
        maxLength = 100
      }
      phoneNumber = {
        type    = "string"
        pattern = "^\\+?[1-9]\\d{1,14}$"
      }
      preferences = {
        type = "object"
        properties = {
          notifications = { type = "boolean" }
          theme        = { type = "string", enum = ["light", "dark"] }
          language     = { type = "string", pattern = "^[a-z]{2}$" }
        }
      }
      metadata = {
        type = "object"
        additionalProperties = true
      }
    }
    additionalProperties = false
  })
}

# Response model for user operations
resource "aws_api_gateway_model" "user_response" {
  rest_api_id  = aws_api_gateway_rest_api.transformation_api.id
  name         = "UserResponse"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "User Response"
    type      = "object"
    properties = {
      success = { type = "boolean" }
      data = {
        type = "object"
        properties = {
          userId     = { type = "string" }
          displayName = { type = "string" }
          contactInfo = {
            type = "object"
            properties = {
              email = { type = "string" }
              phone = { type = "string" }
            }
          }
          createdAt       = { type = "string" }
          profileComplete = { type = "boolean" }
        }
      }
      links = {
        type = "object"
        properties = {
          self    = { type = "string" }
          profile = { type = "string" }
        }
      }
    }
  })
}

# Error response model
resource "aws_api_gateway_model" "error_response" {
  rest_api_id  = aws_api_gateway_rest_api.transformation_api.id
  name         = "ErrorResponse"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Error Response"
    type      = "object"
    required  = ["error", "message"]
    properties = {
      error   = { type = "string" }
      message = { type = "string" }
      details = {
        type = "array"
        items = {
          type = "object"
          properties = {
            field   = { type = "string" }
            code    = { type = "string" }
            message = { type = "string" }
          }
        }
      }
      timestamp = { type = "string" }
      path      = { type = "string" }
    }
  })
}

# ===== REQUEST VALIDATOR =====

# Request validator for comprehensive validation
resource "aws_api_gateway_request_validator" "comprehensive_validator" {
  count                       = var.enable_request_validation ? 1 : 0
  rest_api_id                 = aws_api_gateway_rest_api.transformation_api.id
  name                        = "comprehensive-validator"
  validate_request_body       = true
  validate_request_parameters = true
}

# ===== API GATEWAY RESOURCES =====

# /users resource
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  parent_id   = aws_api_gateway_rest_api.transformation_api.root_resource_id
  path_part   = "users"
}

# ===== POST METHOD CONFIGURATION =====

# POST method for creating users
resource "aws_api_gateway_method" "post_users" {
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
  
  request_validator_id = var.enable_request_validation ? aws_api_gateway_request_validator.comprehensive_validator[0].id : null
  request_models = {
    "application/json" = aws_api_gateway_model.user_create_request.name
  }
}

# Lambda integration for POST method
resource "aws_api_gateway_integration" "post_users_integration" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  
  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = aws_lambda_function.data_processor.invoke_arn
  passthrough_behavior   = "NEVER"
  
  # Request transformation template
  request_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
#set($context = $context)
#set($util = $util)

## Transform incoming request to backend format
{
    "user_data": {
        "id": "$util.escapeJavaScript($context.requestId)",
        "first_name": "$util.escapeJavaScript($inputRoot.firstName)",
        "last_name": "$util.escapeJavaScript($inputRoot.lastName)",
        "email": "$util.escapeJavaScript($inputRoot.email.toLowerCase())",
        #if($inputRoot.phoneNumber && $inputRoot.phoneNumber != "")
        "phone": "$util.escapeJavaScript($inputRoot.phoneNumber)",
        #end
        #if($inputRoot.preferences)
        "preferences": {
            #if($inputRoot.preferences.notifications)
            "email_notifications": $inputRoot.preferences.notifications,
            #end
            #if($inputRoot.preferences.theme)
            "ui_theme": "$util.escapeJavaScript($inputRoot.preferences.theme)",
            #end
            #if($inputRoot.preferences.language)
            "locale": "$util.escapeJavaScript($inputRoot.preferences.language)",
            #end
            "auto_save": true
        },
        #end
        "source": "api_gateway",
        "created_via": "rest_api"
    },
    "request_context": {
        "request_id": "$context.requestId",
        "api_id": "$context.apiId",
        "stage": "$context.stage",
        "resource_path": "$context.resourcePath",
        "http_method": "$context.httpMethod",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)",
        "request_time": "$context.requestTime",
        "request_time_epoch": $context.requestTimeEpoch
    },
    #if($inputRoot.metadata)
    "additional_metadata": $input.json('$.metadata'),
    #end
    "processing_flags": {
        "validate_email": true,
        "send_welcome": true,
        "create_profile": true
    }
}
EOF
  }
}

# POST method response (200)
resource "aws_api_gateway_method_response" "post_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = aws_api_gateway_model.user_response.name
  }
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# POST method response (400)
resource "aws_api_gateway_method_response" "post_users_400" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "400"
  
  response_models = {
    "application/json" = aws_api_gateway_model.error_response.name
  }
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# POST method response (500)
resource "aws_api_gateway_method_response" "post_users_500" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = "500"
  
  response_models = {
    "application/json" = aws_api_gateway_model.error_response.name
  }
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# Integration response for POST (200)
resource "aws_api_gateway_integration_response" "post_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = aws_api_gateway_method_response.post_users_200.status_code
  
  # Response transformation template
  response_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
#set($context = $context)

## Transform backend response to standardized API format
{
    "success": true,
    "data": {
        "userId": "$util.escapeJavaScript($inputRoot.id)",
        "displayName": "$util.escapeJavaScript($inputRoot.full_name)",
        "contactInfo": {
            #if($inputRoot.profile.email)
            "email": "$util.escapeJavaScript($inputRoot.profile.email)",
            #end
            #if($inputRoot.profile.phone)
            "phone": "$util.escapeJavaScript($inputRoot.profile.phone)"
            #end
        },
        "createdAt": "$util.escapeJavaScript($inputRoot.processed_at)",
        "profileComplete": #if($inputRoot.profile.email && $inputRoot.full_name != "")true#{else}false#end,
        "preferences": #if($inputRoot.profile.preferences)$input.json('$.profile.preferences')#{else}{}#end
    },
    "metadata": {
        "processingId": "$util.escapeJavaScript($inputRoot.id)",
        "version": #if($inputRoot.metadata.version)"$util.escapeJavaScript($inputRoot.metadata.version)"#{else}"1.0"#end,
        "processedAt": "$util.escapeJavaScript($inputRoot.processed_at)"
    },
    "links": {
        "self": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)",
        "profile": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)/profile"
    }
}
EOF
  }
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }
}

# Integration response for POST (500)
resource "aws_api_gateway_integration_response" "post_users_500" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_users.http_method
  status_code = aws_api_gateway_method_response.post_users_500.status_code
  
  selection_pattern = ".*\"statusCode\": 500.*"
  
  response_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$.errorMessage'))
#set($context = $context)

{
    "error": "PROCESSING_ERROR",
    "message": #if($inputRoot)"$util.escapeJavaScript($inputRoot)"#{else}"An error occurred while processing your request"#end,
    "details": [
        {
            "field": "request",
            "code": "LAMBDA_EXECUTION_ERROR",
            "message": "Backend service encountered an error"
        }
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
EOF
  }
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }
}

# ===== GET METHOD CONFIGURATION =====

# GET method for retrieving users
resource "aws_api_gateway_method" "get_users" {
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"
  
  request_parameters = {
    "method.request.querystring.limit"  = false
    "method.request.querystring.offset" = false
    "method.request.querystring.filter" = false
    "method.request.querystring.sort"   = false
  }
}

# Lambda integration for GET method
resource "aws_api_gateway_integration" "get_users_integration" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  
  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = aws_lambda_function.data_processor.invoke_arn
  
  # Query parameter transformation template
  request_templates = {
    "application/json" = <<EOF
{
    "operation": "list_users",
    "pagination": {
        "limit": #if($input.params('limit'))$input.params('limit')#{else}10#end,
        "offset": #if($input.params('offset'))$input.params('offset')#{else}0#end
    },
    #if($input.params('filter'))
    "filters": {
        #set($filterParam = $input.params('filter'))
        #if($filterParam.contains(':'))
            #set($filterParts = $filterParam.split(':'))
            "$util.escapeJavaScript($filterParts[0])": "$util.escapeJavaScript($filterParts[1])"
        #else
            "search": "$util.escapeJavaScript($filterParam)"
        #end
    },
    #end
    #if($input.params('sort'))
    "sorting": {
        #set($sortParam = $input.params('sort'))
        #if($sortParam.startsWith('-'))
            "field": "$util.escapeJavaScript($sortParam.substring(1))",
            "direction": "desc"
        #else
            "field": "$util.escapeJavaScript($sortParam)",
            "direction": "asc"
        #end
    },
    #end
    "request_context": {
        "request_id": "$context.requestId",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)"
    }
}
EOF
  }
}

# GET method response (200)
resource "aws_api_gateway_method_response" "get_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  status_code = "200"
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# Integration response for GET (200)
resource "aws_api_gateway_integration_response" "get_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.get_users.http_method
  status_code = aws_api_gateway_method_response.get_users_200.status_code
  
  # CORS headers
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }
}

# ===== OPTIONS METHOD FOR CORS =====

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "options_users" {
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Mock integration for OPTIONS
resource "aws_api_gateway_integration" "options_users_integration" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method
  
  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# OPTIONS method response
resource "aws_api_gateway_method_response" "options_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# OPTIONS integration response
resource "aws_api_gateway_integration_response" "options_users_200" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.options_users.http_method
  status_code = aws_api_gateway_method_response.options_users_200.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = join(",", formatlist("'%s'", var.cors_allowed_origins))
    "method.response.header.Access-Control-Allow-Headers" = join(",", formatlist("'%s'", var.cors_allowed_headers))
    "method.response.header.Access-Control-Allow-Methods" = join(",", formatlist("'%s'", var.cors_allowed_methods))
  }
}

# ===== GATEWAY RESPONSES =====

# Gateway response for validation errors
resource "aws_api_gateway_gateway_response" "bad_request_body" {
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  response_type = "BAD_REQUEST_BODY"
  status_code   = "400"
  
  response_templates = {
    "application/json" = <<EOF
{
    "error": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": [
        #foreach($error in $context.error.validationErrorString.split(','))
        {
            "field": #if($error.contains('Invalid request body'))"body"#{elseif($error.contains('required'))$error.split("'")[1]#{else}"unknown"#end,
            "code": "VALIDATION_FAILED",
            "message": "$util.escapeJavaScript($error.trim())"
        }#if($foreach.hasNext),#end
        #end
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
EOF
  }
}

# Gateway response for unauthorized access
resource "aws_api_gateway_gateway_response" "unauthorized" {
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  response_type = "UNAUTHORIZED"
  status_code   = "401"
  
  response_templates = {
    "application/json" = jsonencode({
      error     = "UNAUTHORIZED"
      message   = "Authentication required"
      timestamp = "$context.requestTime"
      path      = "$context.resourcePath"
    })
  }
}

# ===== LAMBDA PERMISSION =====

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.transformation_api.execution_arn}/*/*"
}

# ===== API GATEWAY DEPLOYMENT =====

# API Gateway deployment
resource "aws_api_gateway_deployment" "transformation_api" {
  depends_on = [
    aws_api_gateway_method.post_users,
    aws_api_gateway_method.get_users,
    aws_api_gateway_method.options_users,
    aws_api_gateway_integration.post_users_integration,
    aws_api_gateway_integration.get_users_integration,
    aws_api_gateway_integration.options_users_integration,
    aws_api_gateway_integration_response.post_users_200,
    aws_api_gateway_integration_response.post_users_500,
    aws_api_gateway_integration_response.get_users_200,
    aws_api_gateway_integration_response.options_users_200,
  ]
  
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  description = "Deployment for transformation API with VTL templates"
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "transformation_api" {
  deployment_id = aws_api_gateway_deployment.transformation_api.id
  rest_api_id   = aws_api_gateway_rest_api.transformation_api.id
  stage_name    = var.api_stage_name
  description   = "Stage for transformation API testing and production"
  
  # X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing
  
  # Throttling settings
  throttle_settings {
    rate_limit  = var.throttle_rate_limit
    burst_limit = var.throttle_burst_limit
  }
  
  # CloudWatch logging and metrics
  dynamic "access_log_settings" {
    for_each = var.enable_api_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
        requestLength  = "$context.requestLength"
        sourceIp       = "$context.identity.sourceIp"
        userAgent      = "$context.identity.userAgent"
        error          = "$context.error.message"
        errorType      = "$context.error.messageString"
      })
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-${var.api_stage_name}"
    Description = "API Gateway stage for transformation API"
  })
}

# API Gateway method settings
resource "aws_api_gateway_method_settings" "transformation_api" {
  rest_api_id = aws_api_gateway_rest_api.transformation_api.id
  stage_name  = aws_api_gateway_stage.transformation_api.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled    = var.enable_detailed_metrics
    logging_level      = var.enable_api_logging ? "INFO" : "OFF"
    data_trace_enabled = var.enable_api_logging
    
    # Throttling
    throttling_rate_limit  = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit
  }
}

# ===== CLOUDWATCH RESOURCES =====

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_logging ? 1 : 0
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/apigateway/${local.api_name}"
    Description = "Log group for API Gateway access logs"
  })
}

# CloudWatch Log Group for API Gateway execution logs
resource "aws_cloudwatch_log_group" "api_gateway_execution_logs" {
  count             = var.enable_api_logging ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.transformation_api.id}/${var.api_stage_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.transformation_api.id}/${var.api_stage_name}"
    Description = "Log group for API Gateway execution logs"
  })
}