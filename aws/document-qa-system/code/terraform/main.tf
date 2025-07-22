# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common resource naming
  resource_prefix = "${var.project_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result
  
  # S3 bucket name (either provided or auto-generated)
  bucket_name = var.documents_bucket_name != "" ? var.documents_bucket_name : "${local.resource_prefix}-documents-${local.unique_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

#####################################
# S3 BUCKET FOR DOCUMENT STORAGE
#####################################

# S3 bucket for storing documents
resource "aws_s3_bucket" "documents" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-documents"
    Description = "Document storage for intelligent QA system"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  count  = var.enable_encryption_at_rest ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.kms_key_id != "" ? true : false
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "documents" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  count      = var.s3_lifecycle_enabled ? 1 : 0
  bucket     = aws_s3_bucket.documents.id
  depends_on = [aws_s3_bucket_versioning.documents]

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

#####################################
# IAM ROLES AND POLICIES
#####################################

# IAM role for Kendra
resource "aws_iam_role" "kendra_service_role" {
  name = "${local.resource_prefix}-kendra-service-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kendra.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-kendra-service-role"
    Description = "Service role for Kendra index and data source"
  })
}

# IAM policy for Kendra to access S3 bucket
resource "aws_iam_role_policy" "kendra_s3_policy" {
  name = "KendraS3AccessPolicy"
  role = aws_iam_role.kendra_service_role.id

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
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
      }
    ]
  })
}

# Attach CloudWatch Logs policy to Kendra role
resource "aws_iam_role_policy_attachment" "kendra_cloudwatch_logs" {
  role       = aws_iam_role.kendra_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.resource_prefix}-lambda-execution-role-${local.unique_suffix}"

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
    Name        = "${local.resource_prefix}-lambda-execution-role"
    Description = "Execution role for QA processor Lambda function"
  })
}

# IAM policy for Lambda to access Kendra and Bedrock
resource "aws_iam_role_policy" "lambda_qa_policy" {
  name = "LambdaQAPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kendra:Query",
          "kendra:DescribeIndex"
        ]
        Resource = aws_kendra_index.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#####################################
# AMAZON KENDRA INDEX AND DATA SOURCE
#####################################

# Kendra index
resource "aws_kendra_index" "main" {
  name        = "${local.resource_prefix}-${var.kendra_index_name}-${local.unique_suffix}"
  description = var.kendra_index_description
  edition     = var.kendra_index_edition
  role_arn    = aws_iam_role.kendra_service_role.arn

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-kendra-index"
    Description = "Kendra index for intelligent document search"
  })
}

# Kendra S3 data source
resource "aws_kendra_data_source" "s3_documents" {
  index_id = aws_kendra_index.main.id
  name     = "S3DocumentSource"
  type     = "S3"
  role_arn = aws_iam_role.kendra_service_role.arn

  configuration {
    s3_configuration {
      bucket_name = aws_s3_bucket.documents.bucket

      # Include documents from the documents/ prefix
      inclusion_prefixes = ["documents/"]

      # Optional: Configure metadata
      documents_metadata_configuration {
        s3_prefix = "metadata/"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-s3-data-source"
    Description = "S3 data source for Kendra index"
  })

  depends_on = [
    aws_iam_role_policy.kendra_s3_policy,
    aws_iam_role_policy_attachment.kendra_cloudwatch_logs
  ]
}

#####################################
# LAMBDA FUNCTION FOR QA PROCESSING
#####################################

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/qa-processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      kendra_index_id = aws_kendra_index.main.id
      bedrock_model_id = var.bedrock_model_id
      max_tokens = var.bedrock_max_tokens
    })
    filename = "index.py"
  }
}

# Lambda function
resource "aws_lambda_function" "qa_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.resource_prefix}-${var.lambda_function_name}-${local.unique_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      KENDRA_INDEX_ID  = aws_kendra_index.main.id
      BEDROCK_MODEL_ID = var.bedrock_model_id
      MAX_TOKENS       = tostring(var.bedrock_max_tokens)
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-qa-processor"
    Description = "Lambda function for processing QA requests"
  })

  depends_on = [
    aws_iam_role_policy.lambda_qa_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-${var.lambda_function_name}-${local.unique_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-lambda-logs"
    Description = "CloudWatch logs for QA processor Lambda"
  })
}

#####################################
# API GATEWAY (OPTIONAL)
#####################################

# API Gateway REST API
resource "aws_api_gateway_rest_api" "qa_api" {
  count       = var.enable_api_gateway ? 1 : 0
  name        = "${local.resource_prefix}-qa-api-${local.unique_suffix}"
  description = "REST API for intelligent document QA system"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-qa-api"
    Description = "API Gateway for QA system"
  })
}

# API Gateway resource
resource "aws_api_gateway_resource" "qa_resource" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.qa_api[0].id
  parent_id   = aws_api_gateway_rest_api.qa_api[0].root_resource_id
  path_part   = "ask"
}

# API Gateway method
resource "aws_api_gateway_method" "qa_method" {
  count         = var.enable_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.qa_api[0].id
  resource_id   = aws_api_gateway_resource.qa_resource[0].id
  http_method   = "POST"
  authorization = var.enable_api_key ? "API_KEY" : "NONE"
  api_key_required = var.enable_api_key
}

# API Gateway integration
resource "aws_api_gateway_integration" "qa_integration" {
  count                   = var.enable_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.qa_api[0].id
  resource_id             = aws_api_gateway_resource.qa_resource[0].id
  http_method             = aws_api_gateway_method.qa_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.qa_processor.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  count         = var.enable_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.qa_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.qa_api[0].execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "qa_deployment" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.qa_api[0].id
  stage_name  = var.api_gateway_stage_name

  depends_on = [
    aws_api_gateway_method.qa_method,
    aws_api_gateway_integration.qa_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Key (optional)
resource "aws_api_gateway_api_key" "qa_api_key" {
  count       = var.enable_api_gateway && var.enable_api_key ? 1 : 0
  name        = "${local.resource_prefix}-qa-api-key-${local.unique_suffix}"
  description = "API key for QA system access"

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-qa-api-key"
    Description = "API key for accessing QA system"
  })
}

# Usage plan for API key
resource "aws_api_gateway_usage_plan" "qa_usage_plan" {
  count       = var.enable_api_gateway && var.enable_api_key ? 1 : 0
  name        = "${local.resource_prefix}-qa-usage-plan-${local.unique_suffix}"
  description = "Usage plan for QA API"

  api_stages {
    api_id = aws_api_gateway_rest_api.qa_api[0].id
    stage  = aws_api_gateway_deployment.qa_deployment[0].stage_name
  }

  quota_settings {
    limit  = 1000
    period = "MONTH"
  }

  throttle_settings {
    rate_limit  = 10
    burst_limit = 20
  }

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-qa-usage-plan"
    Description = "Usage plan for QA API"
  })
}

# Usage plan key
resource "aws_api_gateway_usage_plan_key" "qa_usage_plan_key" {
  count         = var.enable_api_gateway && var.enable_api_key ? 1 : 0
  key_id        = aws_api_gateway_api_key.qa_api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.qa_usage_plan[0].id
}

#####################################
# CLOUDWATCH MONITORING
#####################################

# CloudWatch log group for Kendra
resource "aws_cloudwatch_log_group" "kendra_logs" {
  name              = "/aws/kendra/${aws_kendra_index.main.name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-kendra-logs"
    Description = "CloudWatch logs for Kendra index"
  })
}

# CloudWatch log group for API Gateway (if enabled)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.qa_api[0].id}/${var.api_gateway_stage_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-api-gateway-logs"
    Description = "CloudWatch logs for API Gateway"
  })
}