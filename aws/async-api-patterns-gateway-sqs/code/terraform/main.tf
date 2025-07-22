# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique resource names
  project_suffix        = "${var.project_name}-${random_id.suffix.hex}"
  main_queue_name      = "${local.project_suffix}-main-queue"
  dlq_name             = "${local.project_suffix}-dlq"
  jobs_table_name      = "${local.project_suffix}-jobs"
  results_bucket_name  = var.s3_bucket_name_override != "" ? var.s3_bucket_name_override : "${local.project_suffix}-results"
  api_name             = "${local.project_suffix}-api"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "asynchronous-api-patterns-api-gateway-sqs"
  })
}

#------------------------------------------------------------------------------
# S3 Bucket for storing job results
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "results" {
  bucket = local.results_bucket_name

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-results-bucket"
    Type = "job-results-storage"
  })
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "job_results_lifecycle"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

#------------------------------------------------------------------------------
# SQS Dead Letter Queue
#------------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = var.sqs_message_retention_period
  visibility_timeout_seconds = var.sqs_visibility_timeout

  # Enable server-side encryption if requested
  dynamic "kms_master_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_master_key_id = "alias/aws/sqs"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-dead-letter-queue"
    Type = "dead-letter-queue"
  })
}

#------------------------------------------------------------------------------
# SQS Main Processing Queue
#------------------------------------------------------------------------------

resource "aws_sqs_queue" "main" {
  name                      = local.main_queue_name
  message_retention_seconds = var.sqs_message_retention_period
  visibility_timeout_seconds = var.sqs_visibility_timeout

  # Configure redrive policy for dead letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.sqs_max_receive_count
  })

  # Enable server-side encryption if requested
  dynamic "kms_master_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_master_key_id = "alias/aws/sqs"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-main-processing-queue"
    Type = "main-processing-queue"
  })
}

#------------------------------------------------------------------------------
# DynamoDB Table for Job Tracking
#------------------------------------------------------------------------------

resource "aws_dynamodb_table" "jobs" {
  name           = local.jobs_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "jobId"

  # Configure read/write capacity only for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "jobId"
    type = "S"
  }

  # Enable server-side encryption
  server_side_encryption {
    enabled = var.enable_encryption
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-jobs-table"
    Type = "job-tracking-database"
  })
}

#------------------------------------------------------------------------------
# IAM Role for API Gateway
#------------------------------------------------------------------------------

# Trust policy for API Gateway
data "aws_iam_policy_document" "api_gateway_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for API Gateway to access SQS
data "aws_iam_policy_document" "api_gateway_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.main.arn]
  }
}

resource "aws_iam_role" "api_gateway" {
  name               = "${local.project_suffix}-api-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-api-gateway-role"
    Type = "api-gateway-service-role"
  })
}

resource "aws_iam_role_policy" "api_gateway_sqs" {
  name   = "SQSAccessPolicy"
  role   = aws_iam_role.api_gateway.id
  policy = data.aws_iam_policy_document.api_gateway_sqs.json
}

#------------------------------------------------------------------------------
# IAM Role for Lambda Functions
#------------------------------------------------------------------------------

# Trust policy for Lambda
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for Lambda to access DynamoDB, S3, and SQS
data "aws_iam_policy_document" "lambda_permissions" {
  # DynamoDB permissions
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.jobs.arn]
  }

  # S3 permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.results.arn}/*"]
  }

  # SQS permissions
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.main.arn]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.project_suffix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-lambda-execution-role"
    Type = "lambda-service-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "LambdaAccessPolicy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

#------------------------------------------------------------------------------
# Lambda Function: Job Processor
#------------------------------------------------------------------------------

# Create ZIP archive for job processor function
data "archive_file" "job_processor" {
  type        = "zip"
  output_path = "${path.module}/job_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/job_processor.py", {
      jobs_table_name      = aws_dynamodb_table.jobs.name
      results_bucket_name  = aws_s3_bucket.results.id
    })
    filename = "job_processor.py"
  }
}

resource "aws_lambda_function" "job_processor" {
  filename         = data.archive_file.job_processor.output_path
  function_name    = "${local.project_suffix}-job-processor"
  role            = aws_iam_role.lambda.arn
  handler         = "job_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.job_processor.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE_NAME      = aws_dynamodb_table.jobs.name
      RESULTS_BUCKET_NAME  = aws_s3_bucket.results.id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-job-processor"
    Type = "job-processing-function"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_permissions,
  ]
}

#------------------------------------------------------------------------------
# Lambda Function: Status Checker
#------------------------------------------------------------------------------

# Create ZIP archive for status checker function
data "archive_file" "status_checker" {
  type        = "zip"
  output_path = "${path.module}/status_checker.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/status_checker.py", {
      jobs_table_name = aws_dynamodb_table.jobs.name
    })
    filename = "status_checker.py"
  }
}

resource "aws_lambda_function" "status_checker" {
  filename         = data.archive_file.status_checker.output_path
  function_name    = "${local.project_suffix}-status-checker"
  role            = aws_iam_role.lambda.arn
  handler         = "status_checker.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.status_checker.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE_NAME = aws_dynamodb_table.jobs.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-status-checker"
    Type = "status-checking-function"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_permissions,
  ]
}

#------------------------------------------------------------------------------
# Lambda Event Source Mapping for SQS
#------------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.main.arn
  function_name                      = aws_lambda_function.job_processor.arn
  batch_size                         = var.lambda_event_source_batch_size
  maximum_batching_window_in_seconds = var.lambda_event_source_max_batching_window

  depends_on = [aws_iam_role_policy.lambda_permissions]
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda Functions
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "job_processor" {
  name              = "/aws/lambda/${aws_lambda_function.job_processor.function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-job-processor-logs"
    Type = "lambda-log-group"
  })
}

resource "aws_cloudwatch_log_group" "status_checker" {
  name              = "/aws/lambda/${aws_lambda_function.status_checker.function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-status-checker-logs"
    Type = "lambda-log-group"
  })
}

#------------------------------------------------------------------------------
# API Gateway REST API
#------------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "main" {
  name        = local.api_name
  description = "Asynchronous API with SQS integration"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-api-gateway"
    Type = "rest-api-gateway"
  })
}

#------------------------------------------------------------------------------
# API Gateway Resources and Methods: /submit endpoint
#------------------------------------------------------------------------------

# Create /submit resource
resource "aws_api_gateway_resource" "submit" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "submit"
}

# POST method for /submit
resource "aws_api_gateway_method" "submit_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submit.id
  http_method   = "POST"
  authorization = "NONE"
}

# CORS OPTIONS method for /submit
resource "aws_api_gateway_method" "submit_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.submit.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# SQS integration for /submit POST
resource "aws_api_gateway_integration" "submit_sqs" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.submit.id
  http_method             = aws_api_gateway_method.submit_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.main.name}"
  credentials             = aws_iam_role.api_gateway.arn

  request_parameters = {
    "integration.request.header.Content-Type"     = "'application/x-amz-json-1.0'"
    "integration.request.querystring.Action"      = "'SendMessage'"
    "integration.request.querystring.MessageBody" = "method.request.body"
  }

  request_templates = {
    "application/json" = jsonencode({
      jobId     = "$context.requestId"
      data      = "$input.json('$')"
      timestamp = "$context.requestTime"
    })
  }
}

# CORS integration for /submit OPTIONS
resource "aws_api_gateway_integration" "submit_cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submit.id
  http_method = aws_api_gateway_method.submit_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

# Method response for /submit POST
resource "aws_api_gateway_method_response" "submit_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submit.id
  http_method = aws_api_gateway_method.submit_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  dynamic "response_parameters" {
    for_each = var.enable_cors ? [1] : []
    content {
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = true
      }
    }
  }
}

# Method response for /submit OPTIONS
resource "aws_api_gateway_method_response" "submit_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submit.id
  http_method = aws_api_gateway_method.submit_options[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for /submit POST
resource "aws_api_gateway_integration_response" "submit_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submit.id
  http_method = aws_api_gateway_method.submit_post.http_method
  status_code = aws_api_gateway_method_response.submit_post.status_code

  response_templates = {
    "application/json" = jsonencode({
      jobId   = "$context.requestId"
      status  = "queued"
      message = "Job submitted successfully"
    })
  }

  dynamic "response_parameters" {
    for_each = var.enable_cors ? [1] : []
    content {
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
      }
    }
  }
}

# Integration response for /submit OPTIONS
resource "aws_api_gateway_integration_response" "submit_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.submit.id
  http_method = aws_api_gateway_method.submit_options[0].http_method
  status_code = aws_api_gateway_method_response.submit_options[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_allow_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_allow_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_allow_origins)}'"
  }
}

#------------------------------------------------------------------------------
# API Gateway Resources and Methods: /status/{jobId} endpoint
#------------------------------------------------------------------------------

# Create /status resource
resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "status"
}

# Create {jobId} resource under /status
resource "aws_api_gateway_resource" "status_job_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.status.id
  path_part   = "{jobId}"
}

# GET method for /status/{jobId}
resource "aws_api_gateway_method" "status_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.status_job_id.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.jobId" = true
  }
}

# CORS OPTIONS method for /status/{jobId}
resource "aws_api_gateway_method" "status_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.status_job_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Lambda integration for /status/{jobId} GET
resource "aws_api_gateway_integration" "status_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.status_job_id.id
  http_method             = aws_api_gateway_method.status_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.status_checker.invoke_arn
}

# CORS integration for /status/{jobId} OPTIONS
resource "aws_api_gateway_integration" "status_cors" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.status_job_id.id
  http_method = aws_api_gateway_method.status_options[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

# Method response for /status/{jobId} OPTIONS
resource "aws_api_gateway_method_response" "status_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.status_job_id.id
  http_method = aws_api_gateway_method.status_options[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for /status/{jobId} OPTIONS
resource "aws_api_gateway_integration_response" "status_options" {
  count = var.enable_cors ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.status_job_id.id
  http_method = aws_api_gateway_method.status_options[0].http_method
  status_code = aws_api_gateway_method_response.status_options[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_allow_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_allow_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_allow_origins)}'"
  }
}

#------------------------------------------------------------------------------
# Lambda Permissions for API Gateway
#------------------------------------------------------------------------------

resource "aws_lambda_permission" "api_gateway_status_checker" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status_checker.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

#------------------------------------------------------------------------------
# API Gateway Deployment
#------------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.api_stage_name

  depends_on = [
    aws_api_gateway_method.submit_post,
    aws_api_gateway_method.status_get,
    aws_api_gateway_integration.submit_sqs,
    aws_api_gateway_integration.status_lambda,
    aws_api_gateway_integration_response.submit_post,
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-api-deployment"
    Type = "api-gateway-deployment"
  })
}

#------------------------------------------------------------------------------
# API Gateway Stage
#------------------------------------------------------------------------------

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_stage_name

  # Enable throttling
  throttle_settings {
    burst_limit = var.api_throttle_burst_limit
    rate_limit  = var.api_throttle_rate_limit
  }

  # Enable access logging if requested
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
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
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-api-stage"
    Type = "api-gateway-stage"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for API Gateway (optional)
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.enable_api_gateway_logging ? 1 : 0

  name              = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.project_suffix}-api-gateway-logs"
    Type = "api-gateway-log-group"
  })
}

#------------------------------------------------------------------------------
# Create Lambda function source files
#------------------------------------------------------------------------------

# Create the lambda_functions directory and source files
resource "local_file" "lambda_functions_dir" {
  content  = ""
  filename = "${path.module}/lambda_functions/.gitkeep"
}

# Job Processor Lambda function source code
resource "local_file" "job_processor_source" {
  content = <<-EOF
import json
import boto3
import os
import time
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    results_bucket = os.environ['RESULTS_BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        try:
            # Parse message from SQS
            message_body = json.loads(record['body'])
            job_id = message_body['jobId']
            job_data = message_body['data']
            
            # Create initial job record
            table.put_item(
                Item={
                    'jobId': job_id,
                    'status': 'queued',
                    'data': job_data,
                    'createdAt': datetime.now(timezone.utc).isoformat(),
                    'updatedAt': datetime.now(timezone.utc).isoformat()
                }
            )
            
            # Update job status to processing
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'processing',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            # Simulate processing work (replace with actual processing logic)
            print(f"Processing job {job_id} with data: {job_data}")
            time.sleep(10)  # Simulate work
            
            # Generate result
            result = {
                'jobId': job_id,
                'result': f'Processed data: {job_data}',
                'processedAt': datetime.now(timezone.utc).isoformat(),
                'inputData': job_data
            }
            
            # Store result in S3
            s3.put_object(
                Bucket=results_bucket,
                Key=f'results/{job_id}.json',
                Body=json.dumps(result, indent=2),
                ContentType='application/json'
            )
            
            # Update job status to completed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #result = :result, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#result': 'result',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'completed',
                    ':result': f's3://{results_bucket}/results/{job_id}.json',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            print(f"Successfully processed job {job_id}")
            
        except Exception as e:
            print(f"Error processing job: {str(e)}")
            # Update job status to failed
            try:
                table.update_item(
                    Key={'jobId': job_id},
                    UpdateExpression='SET #status = :status, #error = :error, #updatedAt = :timestamp',
                    ExpressionAttributeNames={
                        '#status': 'status',
                        '#error': 'error',
                        '#updatedAt': 'updatedAt'
                    },
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': str(e),
                        ':timestamp': datetime.now(timezone.utc).isoformat()
                    }
                )
            except Exception as update_error:
                print(f"Failed to update job status to failed: {str(update_error)}")
            
            # Re-raise the exception to trigger SQS retry mechanism
            raise
    
    return {'statusCode': 200, 'body': 'Processing complete'}
EOF

  filename = "${path.module}/lambda_functions/job_processor.py"
  
  depends_on = [local_file.lambda_functions_dir]
}

# Status Checker Lambda function source code
resource "local_file" "status_checker_source" {
  content = <<-EOF
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    table = dynamodb.Table(table_name)
    
    # Extract job ID from path parameters
    job_id = event['pathParameters']['jobId']
    
    try:
        # Query DynamoDB for job status
        response = table.get_item(Key={'jobId': job_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                    'Access-Control-Allow-Methods': 'GET,OPTIONS'
                },
                'body': json.dumps({
                    'error': 'Job not found',
                    'jobId': job_id
                })
            }
        
        job = response['Item']
        
        # Prepare response data
        response_data = {
            'jobId': job['jobId'],
            'status': job['status'],
            'createdAt': job['createdAt'],
            'updatedAt': job.get('updatedAt', job['createdAt'])
        }
        
        # Include result or error information if available
        if 'result' in job:
            response_data['result'] = job['result']
        
        if 'error' in job:
            response_data['error'] = job['error']
        
        if 'data' in job:
            response_data['inputData'] = job['data']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        print(f"Error retrieving job status: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }
EOF

  filename = "${path.module}/lambda_functions/status_checker.py"
  
  depends_on = [local_file.lambda_functions_dir]
}