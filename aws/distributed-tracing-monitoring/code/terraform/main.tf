# Main Terraform configuration for AWS X-Ray Infrastructure Monitoring

# Data sources
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
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Resource names
  orders_table_name    = "${var.project_name}-orders-${local.suffix}"
  lambda_role_name     = "${var.project_name}-lambda-role-${local.suffix}"
  api_gateway_name     = "${var.project_name}-api-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "infrastructure-monitoring-aws-x-ray"
    },
    var.additional_tags
  )
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name

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

# IAM Role Policy Attachments
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_write_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "dynamodb_full_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Additional IAM policy for CloudWatch and X-Ray access
resource "aws_iam_role_policy" "additional_permissions" {
  name = "${var.project_name}-additional-permissions-${local.suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "xray:GetTraceSummaries",
          "xray:GetServiceGraph",
          "xray:BatchGetTraces"
        ]
        Resource = "*"
      }
    ]
  })
}

# DynamoDB Table for Orders
resource "aws_dynamodb_table" "orders" {
  name           = local.orders_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }

  # Enable X-Ray tracing for DynamoDB
  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# Lambda Function: Order Processor
data "archive_file" "order_processor" {
  type        = "zip"
  output_path = "/tmp/order-processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/order_processor.py", {
      orders_table = aws_dynamodb_table.orders.name
    })
    filename = "order-processor.py"
  }
  
  source {
    content = file("${path.module}/lambda_functions/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "aws_lambda_function" "order_processor" {
  filename         = data.archive_file.order_processor.output_path
  function_name    = "${var.project_name}-order-processor-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "order-processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.order_processor.output_base64sha256

  environment {
    variables = {
      ORDERS_TABLE = aws_dynamodb_table.orders.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.xray_write_access,
    aws_cloudwatch_log_group.order_processor
  ]
}

# CloudWatch Log Group for Order Processor
resource "aws_cloudwatch_log_group" "order_processor" {
  name              = "/aws/lambda/${var.project_name}-order-processor-${local.suffix}"
  retention_in_days = 14
  tags             = local.common_tags
}

# Lambda Function: Inventory Manager
data "archive_file" "inventory_manager" {
  type        = "zip"
  output_path = "/tmp/inventory-manager.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/inventory_manager.py")
    filename = "inventory-manager.py"
  }
  
  source {
    content = file("${path.module}/lambda_functions/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "aws_lambda_function" "inventory_manager" {
  filename         = data.archive_file.inventory_manager.output_path
  function_name    = "${var.project_name}-inventory-manager-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "inventory-manager.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inventory_manager.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.xray_write_access,
    aws_cloudwatch_log_group.inventory_manager
  ]
}

# CloudWatch Log Group for Inventory Manager
resource "aws_cloudwatch_log_group" "inventory_manager" {
  name              = "/aws/lambda/${var.project_name}-inventory-manager-${local.suffix}"
  retention_in_days = 14
  tags             = local.common_tags
}

# Lambda Function: Trace Analyzer
data "archive_file" "trace_analyzer" {
  type        = "zip"
  output_path = "/tmp/trace-analyzer.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/trace_analyzer.py")
    filename = "trace-analyzer.py"
  }
}

resource "aws_lambda_function" "trace_analyzer" {
  filename         = data.archive_file.trace_analyzer.output_path
  function_name    = "${var.project_name}-trace-analyzer-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "trace-analyzer.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.trace_analyzer.output_base64sha256

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.trace_analyzer
  ]
}

# CloudWatch Log Group for Trace Analyzer
resource "aws_cloudwatch_log_group" "trace_analyzer" {
  name              = "/aws/lambda/${var.project_name}-trace-analyzer-${local.suffix}"
  retention_in_days = 14
  tags             = local.common_tags
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = local.api_gateway_name
  description = "API for X-Ray monitoring demo"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway Resource: /orders
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "orders"
}

# API Gateway Method: POST /orders
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "orders_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.order_processor.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_method.orders_post,
    aws_api_gateway_integration.orders_post
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.orders_post.id,
      aws_api_gateway_integration.orders_post.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage with X-Ray Tracing
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_gateway_stage_name

  xray_tracing_enabled = true

  tags = local.common_tags
}

# X-Ray Sampling Rules
resource "aws_xray_sampling_rule" "high_priority" {
  rule_name      = "high-priority-requests-${local.suffix}"
  priority       = 100
  version        = 1
  reservoir_size = var.xray_reservoir_size
  fixed_rate     = var.xray_sampling_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "order-processor"
  resource_arn   = "*"
}

resource "aws_xray_sampling_rule" "error_traces" {
  rule_name      = "error-traces-${local.suffix}"
  priority       = 50
  version        = 1
  reservoir_size = 5
  fixed_rate     = 1.0
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"
}

# EventBridge Rule for Trace Analysis
resource "aws_cloudwatch_event_rule" "trace_analysis" {
  name                = "${var.project_name}-trace-analysis-${local.suffix}"
  description         = "Triggers trace analysis Lambda function"
  schedule_expression = var.trace_analysis_schedule
  state               = "ENABLED"

  tags = local.common_tags
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "trace_analysis" {
  rule      = aws_cloudwatch_event_rule.trace_analysis.name
  target_id = "TraceAnalysisTarget"
  arn       = aws_lambda_function.trace_analyzer.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trace_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trace_analysis.arn
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "xray_monitoring" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-xray-monitoring-${local.suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/X-Ray", "TracesReceived"],
            ["AWS/X-Ray", "TracesScanned"],
            ["AWS/X-Ray", "LatencyHigh"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "X-Ray Trace Metrics"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.order_processor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.order_processor.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.order_processor.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
        }
      }
    ]
  })
}

# SNS Topic for Alerts (optional)
resource "aws_sns_topic" "alerts" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-alerts-${local.suffix}"
  tags  = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-high-error-rate-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorTraces"
  namespace           = "XRay/Analysis"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_error_threshold
  alarm_description   = "High error rate detected in X-Ray traces"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-high-latency-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HighLatencyTraces"
  namespace           = "XRay/Analysis"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_latency_threshold
  alarm_description   = "High latency detected in X-Ray traces"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}