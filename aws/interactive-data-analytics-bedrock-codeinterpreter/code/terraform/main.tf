# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - Main Infrastructure

# Get current AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  unique_suffix = random_id.suffix.hex
  
  # Resource names with unique suffix
  bucket_raw_data    = "${local.name_prefix}-raw-data-${local.unique_suffix}"
  bucket_results     = "${local.name_prefix}-results-${local.unique_suffix}"
  lambda_function    = "${local.name_prefix}-orchestrator-${local.unique_suffix}"
  code_interpreter   = "${local.name_prefix}-interpreter-${local.unique_suffix}"
  iam_role           = "${local.name_prefix}-execution-role-${local.unique_suffix}"
  dlq_name           = "${local.name_prefix}-dlq-${local.unique_suffix}"
  api_gateway_name   = "${local.name_prefix}-api-${local.unique_suffix}"

  # Common tags
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
      Recipe      = "bedrock-agentcore-code-interpreter"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 BUCKETS FOR DATA STORAGE
# ============================================================================

# S3 bucket for raw data input with encryption and versioning
resource "aws_s3_bucket" "raw_data" {
  bucket = local.bucket_raw_data
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for analysis results with encryption and versioning
resource "aws_s3_bucket" "results" {
  bucket = local.bucket_results
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    id     = "analytics_data_lifecycle"
    status = "Enabled"

    filter {
      prefix = "datasets/"
    }

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_glacier_transition_days
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "results_retention"
    status = "Enabled"

    filter {
      prefix = "analysis_results/"
    }

    expiration {
      days = var.s3_results_expiration_days
    }
  }
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for Lambda function and Bedrock AgentCore
resource "aws_iam_role" "execution_role" {
  name = local.iam_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "bedrock.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Custom IAM policy for enhanced analytics permissions
resource "aws_iam_policy" "analytics_policy" {
  name        = "${local.name_prefix}-analytics-policy-${local.unique_suffix}"
  description = "Enhanced policy for Bedrock AgentCore and analytics operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:GetModelInvocationLoggingConfiguration",
          "bedrock:PutModelInvocationLoggingConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.results.arn,
          "${aws_s3_bucket.results.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.dlq.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "analytics_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = aws_iam_policy.analytics_policy.arn
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# LAMBDA FUNCTION FOR ORCHESTRATION
# ============================================================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      code_interpreter_id = local.code_interpreter_id
      bucket_raw_data     = aws_s3_bucket.raw_data.bucket
      bucket_results      = aws_s3_bucket.results.bucket
    })
    filename = "lambda_function.py"
  }
  
  depends_on = [null_resource.code_interpreter]
}

# Lambda function for analytics orchestration
resource "aws_lambda_function" "orchestrator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function
  role            = aws_iam_role.execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CODE_INTERPRETER_ID = local.code_interpreter_id
      BUCKET_RAW_DATA     = aws_s3_bucket.raw_data.bucket
      BUCKET_RESULTS      = aws_s3_bucket.results.bucket
      BEDROCK_MODEL_ID    = var.bedrock_model_id
    }
  }

  # Optional X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.analytics_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# Lambda reserved concurrency
resource "aws_lambda_reserved_concurrency" "orchestrator" {
  function_name                = aws_lambda_function.orchestrator.function_name
  reserved_concurrent_executions = var.lambda_reserved_concurrency
}

# Lambda function event invoke configuration for retry policy
resource "aws_lambda_function_event_invoke_config" "orchestrator" {
  function_name                = aws_lambda_function.orchestrator.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  dead_letter_config {
    destination = aws_sqs_queue.dlq.arn
  }
}

# ============================================================================
# BEDROCK AGENTCORE CODE INTERPRETER
# ============================================================================

# Note: Bedrock AgentCore Code Interpreter is a newer service that may not yet have
# full Terraform resource support. Using null_resource with local-exec as a workaround.

# Create Code Interpreter using AWS CLI (temporary solution until Terraform support)
resource "null_resource" "code_interpreter" {
  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore create-code-interpreter \
        --region ${data.aws_region.current.name} \
        --name ${local.code_interpreter} \
        --description "Interactive data analytics interpreter for processing S3 datasets" \
        --network-configuration '{"networkMode": "PUBLIC"}' \
        --execution-role-arn ${aws_iam_role.execution_role.arn} \
        --output json > code_interpreter_output.json
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      CODE_INTERPRETER_ID=$(cat code_interpreter_output.json | jq -r '.codeInterpreterIdentifier' 2>/dev/null || echo "")
      if [ ! -z "$CODE_INTERPRETER_ID" ] && [ "$CODE_INTERPRETER_ID" != "null" ]; then
        aws bedrock-agentcore delete-code-interpreter \
          --region ${data.aws_region.current.name} \
          --code-interpreter-identifier $CODE_INTERPRETER_ID || true
      fi
      rm -f code_interpreter_output.json
    EOT
  }

  depends_on = [aws_iam_role.execution_role]

  triggers = {
    name               = local.code_interpreter
    execution_role_arn = aws_iam_role.execution_role.arn
  }
}

# Data source to read the Code Interpreter ID after creation
data "local_file" "code_interpreter_output" {
  filename = "code_interpreter_output.json"
  depends_on = [null_resource.code_interpreter]
}

locals {
  code_interpreter_data = jsondecode(data.local_file.code_interpreter_output.content)
  code_interpreter_id   = local.code_interpreter_data.codeInterpreterIdentifier
}

# ============================================================================
# SQS DEAD LETTER QUEUE
# ============================================================================

# Dead letter queue for failed Lambda executions
resource "aws_sqs_queue" "dlq" {
  name                       = local.dlq_name
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600  # 14 days
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sqs"

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH MONITORING AND LOGGING
# ============================================================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = local.common_tags
}

# CloudWatch log group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter_logs" {
  name              = "/aws/bedrock/agentcore/${local.code_interpreter}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = local.common_tags
}

# CloudWatch alarm for execution errors
resource "aws_cloudwatch_metric_alarm" "execution_errors" {
  alarm_name          = "${local.name_prefix}-execution-errors-${local.unique_suffix}"
  alarm_description   = "Alert on analytics execution errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ExecutionErrors"
  namespace           = "Analytics/CodeInterpreter"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_threshold_errors
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.name_prefix}-lambda-duration-${local.unique_suffix}"
  alarm_description   = "Alert on high Lambda execution duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 240000  # 4 minutes in milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.orchestrator.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.unique_suffix}"
  alarm_description   = "Alert on Lambda function errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.orchestrator.function_name
  }

  tags = local.common_tags
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "analytics" {
  dashboard_name = "${local.name_prefix}-dashboard-${local.unique_suffix}"

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
            ["Analytics/CodeInterpreter", "ExecutionCount"],
            [".", "ExecutionErrors"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Analytics Execution Metrics"
          view   = "timeSeries"
          stacked = false
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.orchestrator.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
          view   = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}

# ============================================================================
# API GATEWAY (OPTIONAL)
# ============================================================================

# REST API Gateway for external access
resource "aws_api_gateway_rest_api" "analytics" {
  count       = var.enable_api_gateway ? 1 : 0
  name        = local.api_gateway_name
  description = "Interactive Data Analytics API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway resource
resource "aws_api_gateway_resource" "analytics" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.analytics[0].id
  parent_id   = aws_api_gateway_rest_api.analytics[0].root_resource_id
  path_part   = "analytics"
}

# API Gateway method
resource "aws_api_gateway_method" "analytics_post" {
  count         = var.enable_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.analytics[0].id
  resource_id   = aws_api_gateway_resource.analytics[0].id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "analytics" {
  count                   = var.enable_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.analytics[0].id
  resource_id             = aws_api_gateway_resource.analytics[0].id
  http_method             = aws_api_gateway_method.analytics_post[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orchestrator.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "analytics" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.analytics[0].id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_method.analytics_post,
    aws_api_gateway_integration.analytics
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.analytics[0].id,
      aws_api_gateway_method.analytics_post[0].id,
      aws_api_gateway_integration.analytics[0].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway method settings for throttling
resource "aws_api_gateway_method_settings" "analytics" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.analytics[0].id
  stage_name  = aws_api_gateway_deployment.analytics[0].stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.api_gateway_throttle_rate
    throttling_burst_limit = var.api_gateway_throttle_burst
    logging_level          = var.enable_detailed_monitoring ? "INFO" : "ERROR"
    data_trace_enabled     = var.enable_detailed_monitoring
    metrics_enabled        = true
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count         = var.enable_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.analytics[0].execution_arn}/*/*"
}

# ============================================================================
# SAMPLE DATA UPLOAD (OPTIONAL)
# ============================================================================

# Sample sales data
resource "aws_s3_object" "sample_sales_data" {
  bucket = aws_s3_bucket.raw_data.bucket
  key    = "datasets/sample_sales_data.csv"
  
  content = templatefile("${path.module}/sample_data/sales_data.csv.tpl", {})
  
  tags = local.common_tags
}

# Sample customer data
resource "aws_s3_object" "sample_customer_data" {
  bucket = aws_s3_bucket.raw_data.bucket
  key    = "datasets/sample_customer_data.json"
  
  content = templatefile("${path.module}/sample_data/customer_data.json.tpl", {})
  
  tags = local.common_tags
}