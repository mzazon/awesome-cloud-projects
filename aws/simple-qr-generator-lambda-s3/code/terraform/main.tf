# main.tf
# Main Terraform configuration for AWS QR Code Generator

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Resource naming with consistent suffix
  bucket_name        = "${var.project_name}-bucket-${random_string.suffix.result}"
  function_name      = "${var.project_name}-function-${random_string.suffix.result}"
  role_name         = "${var.project_name}-role-${random_string.suffix.result}"
  api_name          = "${var.project_name}-api-${random_string.suffix.result}"
  log_group_name    = "/aws/lambda/${local.function_name}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    CreatedBy   = "Terraform"
  })
}

# ===== S3 BUCKET FOR QR CODE STORAGE =====

# S3 bucket for storing generated QR code images
resource "aws_s3_bucket" "qr_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "QR Code Storage"
    PublicRead  = "true"
  })
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "qr_bucket_versioning" {
  bucket = aws_s3_bucket.qr_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "qr_bucket_encryption" {
  bucket = aws_s3_bucket.qr_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public ACLs but allow public policies (for public read access)
resource "aws_s3_bucket_public_access_block" "qr_bucket_pab" {
  bucket = aws_s3_bucket.qr_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy for public read access to QR code images
resource "aws_s3_bucket_policy" "qr_bucket_policy" {
  bucket = aws_s3_bucket.qr_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.qr_bucket_pab]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.qr_bucket.arn}/*"
      }
    ]
  })
}

# Configure CORS for web applications
resource "aws_s3_bucket_cors_configuration" "qr_bucket_cors" {
  bucket = aws_s3_bucket.qr_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ===== IAM ROLE AND POLICIES FOR LAMBDA =====

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
    Name    = local.role_name
    Purpose = "Lambda Execution Role"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "S3AccessPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.qr_bucket.arn}/*"
      }
    ]
  })
}

# ===== CLOUDWATCH LOG GROUP =====

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name    = local.log_group_name
    Purpose = "Lambda Function Logs"
  })
}

# ===== LAMBDA FUNCTION =====

# Create the Lambda function Python file
resource "local_file" "lambda_function" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    bucket_name = local.bucket_name
  })
  filename = "${path.module}/lambda_function.py"
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/qr_function.zip"
  
  source {
    content  = local_file.lambda_function.content
    filename = "lambda_function.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
  
  depends_on = [local_file.lambda_function]
}

# Lambda function for QR code generation
resource "aws_lambda_function" "qr_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.qr_bucket.id
      AWS_REGION  = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name    = local.function_name
    Purpose = "QR Code Generator"
  })
}

# ===== API GATEWAY =====

# REST API Gateway
resource "aws_api_gateway_rest_api" "qr_api" {
  name        = local.api_name
  description = "QR Code Generator API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name    = local.api_name
    Purpose = "QR Code Generator API"
  })
}

# API Gateway resource for /generate endpoint
resource "aws_api_gateway_resource" "generate_resource" {
  rest_api_id = aws_api_gateway_rest_api.qr_api.id
  parent_id   = aws_api_gateway_rest_api.qr_api.root_resource_id
  path_part   = "generate"
}

# POST method for /generate endpoint
resource "aws_api_gateway_method" "generate_post" {
  rest_api_id   = aws_api_gateway_rest_api.qr_api.id
  resource_id   = aws_api_gateway_resource.generate_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.qr_api.id
  resource_id = aws_api_gateway_resource.generate_resource.id
  http_method = aws_api_gateway_method.generate_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.qr_generator.invoke_arn
}

# CORS support for OPTIONS method (if enabled)
resource "aws_api_gateway_method" "generate_options" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id   = aws_api_gateway_rest_api.qr_api.id
  resource_id   = aws_api_gateway_resource.generate_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.qr_api.id
  resource_id = aws_api_gateway_resource.generate_resource.id
  http_method = aws_api_gateway_method.generate_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options_response" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.qr_api.id
  resource_id = aws_api_gateway_resource.generate_resource.id
  http_method = aws_api_gateway_method.generate_options[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.qr_api.id
  resource_id = aws_api_gateway_resource.generate_resource.id
  http_method = aws_api_gateway_method.generate_options[0].http_method
  status_code = aws_api_gateway_method_response.options_response[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.qr_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.qr_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.generate_post,
    aws_api_gateway_integration.lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.qr_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.generate_resource.id,
      aws_api_gateway_method.generate_post.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.qr_api.id
  stage_name    = "prod"

  # Enable throttling
  throttle_settings {
    burst_limit = var.api_throttle_burst_limit
    rate_limit  = var.api_throttle_rate_limit
  }

  # Enable access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      extendedRequestId = "$context.extendedRequestId"
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

  tags = merge(local.common_tags, {
    Name    = "${local.api_name}-prod"
    Purpose = "Production API Stage"
  })
}

# CloudWatch log group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name    = "/aws/apigateway/${local.api_name}"
    Purpose = "API Gateway Access Logs"
  })
}