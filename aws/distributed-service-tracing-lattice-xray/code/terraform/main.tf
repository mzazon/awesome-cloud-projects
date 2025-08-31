# Main Terraform configuration for Distributed Service Tracing with VPC Lattice and X-Ray
# This configuration creates a complete microservices observability solution

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags applied to all resources
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Recipe      = "vpc-lattice-xray-tracing"
    CreatedBy   = "terraform"
  }
  
  # Determine VPC and subnet to use
  vpc_id    = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  subnet_id = var.create_vpc ? aws_subnet.main[0].id : var.existing_subnet_id
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# Create VPC for the microservices (if requested)
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-${local.name_suffix}"
  })
}

# Create subnet for Lambda functions (if creating VPC)
resource "aws_subnet" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id               = aws_vpc.main[0].id
  cidr_block           = var.subnet_cidr
  availability_zone    = "${data.aws_region.current.name}${var.availability_zone}"
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet-${local.name_suffix}"
  })
}

# Internet Gateway for VPC (if creating VPC)
resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw-${local.name_suffix}"
  })
}

# Route table for subnet (if creating VPC)
resource "aws_route_table" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-${local.name_suffix}"
  })
}

# Associate route table with subnet (if creating VPC)
resource "aws_route_table_association" "main" {
  count = var.create_vpc ? 1 : 0
  
  subnet_id      = aws_subnet.main[0].id
  route_table_id = aws_route_table.main[0].id
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for Lambda functions with X-Ray permissions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-xray-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray daemon write access policy
resource "aws_iam_role_policy_attachment" "lambda_xray_write" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Additional policy for Lambda inter-service communication
resource "aws_iam_role_policy" "lambda_invoke_policy" {
  name = "${local.name_prefix}-lambda-invoke-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-*"
        ]
      }
    ]
  })
}

# ============================================================================
# LAMBDA LAYER FOR X-RAY SDK
# ============================================================================

# Create X-Ray SDK Lambda layer
data "archive_file" "xray_layer" {
  type        = "zip"
  output_path = "${path.module}/xray-layer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/requirements.txt", {})
    filename = "requirements.txt"
  }
  
  source {
    content = templatefile("${path.module}/lambda_code/build_layer.py", {})
    filename = "build_layer.py"
  }
}

# Lambda layer with X-Ray SDK
resource "aws_lambda_layer_version" "xray_sdk" {
  filename                 = data.archive_file.xray_layer.output_path
  layer_name               = "${local.name_prefix}-xray-sdk-${local.name_suffix}"
  description              = "AWS X-Ray SDK for Python with distributed tracing support"
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = ["x86_64"]
  
  source_code_hash = data.archive_file.xray_layer.output_base64sha256
}

# ============================================================================
# LAMBDA FUNCTIONS FOR MICROSERVICES
# ============================================================================

# Order Service Lambda Function
data "archive_file" "order_service" {
  type        = "zip"
  output_path = "${path.module}/order-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/order_service.py", {
      payment_function_name   = "${local.name_prefix}-payment-service-${local.name_suffix}"
      inventory_function_name = "${local.name_prefix}-inventory-service-${local.name_suffix}"
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "order_service" {
  filename         = data.archive_file.order_service.output_path
  function_name    = "${local.name_prefix}-order-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.order_service.output_base64sha256
  
  layers = [aws_lambda_layer_version.xray_sdk.arn]
  
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      PAYMENT_FUNCTION_NAME   = "${local.name_prefix}-payment-service-${local.name_suffix}"
      INVENTORY_FUNCTION_NAME = "${local.name_prefix}-inventory-service-${local.name_suffix}"
      _X_AMZN_TRACE_ID       = ""
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-order-service-${local.name_suffix}"
    ServiceType = "order-processing"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.order_service,
  ]
}

# Payment Service Lambda Function
data "archive_file" "payment_service" {
  type        = "zip"
  output_path = "${path.module}/payment-service.zip"
  
  source {
    content = file("${path.module}/lambda_code/payment_service.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "payment_service" {
  filename         = data.archive_file.payment_service.output_path
  function_name    = "${local.name_prefix}-payment-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.payment_service.output_base64sha256
  
  layers = [aws_lambda_layer_version.xray_sdk.arn]
  
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      PAYMENT_GATEWAY = "stripe"
      _X_AMZN_TRACE_ID = ""
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-payment-service-${local.name_suffix}"
    ServiceType = "payment-processing"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.payment_service,
  ]
}

# Inventory Service Lambda Function
data "archive_file" "inventory_service" {
  type        = "zip"
  output_path = "${path.module}/inventory-service.zip"
  
  source {
    content = file("${path.module}/lambda_code/inventory_service.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "inventory_service" {
  filename         = data.archive_file.inventory_service.output_path
  function_name    = "${local.name_prefix}-inventory-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inventory_service.output_base64sha256
  
  layers = [aws_lambda_layer_version.xray_sdk.arn]
  
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      DATABASE_TYPE = "dynamodb"
      _X_AMZN_TRACE_ID = ""
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-inventory-service-${local.name_suffix}"
    ServiceType = "inventory-management"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.inventory_service,
  ]
}

# ============================================================================
# VPC LATTICE INFRASTRUCTURE
# ============================================================================

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = "${local.name_prefix}-network-${local.name_suffix}"
  auth_type = "AWS_IAM"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service-network-${local.name_suffix}"
  })
}

# Associate VPC with Service Network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  service_network_identifier = aws_vpclattice_service_network.main.id
  vpc_identifier             = local.vpc_id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-association-${local.name_suffix}"
  })
}

# Target Group for Order Service
resource "aws_vpclattice_target_group" "order_service" {
  name = "${local.name_prefix}-order-tg-${local.name_suffix}"
  type = "LAMBDA"
  
  config {
    health_check {
      enabled  = true
      protocol = "HTTPS"
      path     = "/health"
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-order-target-group-${local.name_suffix}"
    ServiceType = "order-processing"
  })
}

# Register Lambda with Target Group
resource "aws_vpclattice_target_group_attachment" "order_service" {
  target_group_identifier = aws_vpclattice_target_group.order_service.id
  
  target {
    id = aws_lambda_function.order_service.arn
  }
}

# VPC Lattice Service for Order Processing
resource "aws_vpclattice_service" "order_service" {
  name      = "${local.name_prefix}-order-service-${local.name_suffix}"
  auth_type = "AWS_IAM"
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-order-service-${local.name_suffix}"
    ServiceType = "order-processing"
  })
}

# Listener for Order Service
resource "aws_vpclattice_listener" "order_service" {
  name               = "order-listener"
  protocol           = "HTTPS"
  port               = 443
  service_identifier = aws_vpclattice_service.order_service.id
  
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order_service.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-order-listener-${local.name_suffix}"
  })
}

# Associate Service with Service Network
resource "aws_vpclattice_service_network_service_association" "order_service" {
  service_identifier         = aws_vpclattice_service.order_service.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-order-service-association-${local.name_suffix}"
  })
}

# ============================================================================
# CLOUDWATCH LOGGING AND MONITORING
# ============================================================================

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/aws/lambda/${local.name_prefix}-order-service-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-order-service-logs-${local.name_suffix}"
    ServiceType = "order-processing"
  })
}

resource "aws_cloudwatch_log_group" "payment_service" {
  name              = "/aws/lambda/${local.name_prefix}-payment-service-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-payment-service-logs-${local.name_suffix}"
    ServiceType = "payment-processing"
  })
}

resource "aws_cloudwatch_log_group" "inventory_service" {
  name              = "/aws/lambda/${local.name_prefix}-inventory-service-logs-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-inventory-service-logs-${local.name_suffix}"
    ServiceType = "inventory-management"
  })
}

# CloudWatch Log Group for VPC Lattice Access Logs
resource "aws_cloudwatch_log_group" "vpc_lattice_access_logs" {
  count = var.enable_vpc_lattice_logging ? 1 : 0
  
  name              = "/aws/vpclattice/servicenetwork-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-vpc-lattice-logs-${local.name_suffix}"
    ServiceType = "infrastructure"
  })
}

# VPC Lattice Access Log Subscription
resource "aws_vpclattice_access_log_subscription" "main" {
  count = var.enable_vpc_lattice_logging ? 1 : 0
  
  resource_identifier = aws_vpclattice_service_network.main.id
  destination_arn     = aws_cloudwatch_log_group.vpc_lattice_access_logs[0].arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-log-subscription-${local.name_suffix}"
  })
}

# CloudWatch Dashboard for Observability
resource "aws_cloudwatch_dashboard" "observability" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-observability-${local.name_suffix}"
  
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
            ["AWS/VPC-Lattice", "RequestCount", "ServiceNetwork", aws_vpclattice_service_network.main.id],
            [".", "ResponseTime", ".", "."],
            [".", "ActiveConnectionCount", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "VPC Lattice Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.order_service.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Duration", "FunctionName", aws_lambda_function.payment_service.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Duration", "FunctionName", aws_lambda_function.inventory_service.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Performance Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          metrics = [
            ["AWS/X-Ray", "TracesReceived"],
            [".", "LatencyHigh", "ServiceName", aws_lambda_function.order_service.function_name],
            [".", "ErrorRate", ".", "."],
            [".", "LatencyHigh", "ServiceName", aws_lambda_function.payment_service.function_name],
            [".", "ErrorRate", ".", "."],
            [".", "LatencyHigh", "ServiceName", aws_lambda_function.inventory_service.function_name],
            [".", "ErrorRate", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "X-Ray Trace Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ============================================================================
# TEST TRAFFIC GENERATION (OPTIONAL)
# ============================================================================

# Test Traffic Generator Lambda Function (optional)
data "archive_file" "test_generator" {
  count = var.test_traffic_generation ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/test-generator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/test_generator.py", {
      order_function_name = aws_lambda_function.order_service.function_name
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "test_generator" {
  count = var.test_traffic_generation ? 1 : 0
  
  filename         = data.archive_file.test_generator[0].output_path
  function_name    = "${local.name_prefix}-test-generator-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = 512
  source_code_hash = data.archive_file.test_generator[0].output_base64sha256
  
  environment {
    variables = {
      ORDER_FUNCTION_NAME = aws_lambda_function.order_service.function_name
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-test-generator-${local.name_suffix}"
    ServiceType = "testing"
  })
}

# EventBridge rule to trigger test traffic generation (optional)
resource "aws_cloudwatch_event_rule" "test_traffic" {
  count = var.test_traffic_generation ? 1 : 0
  
  name                = "${local.name_prefix}-test-traffic-${local.name_suffix}"
  description         = "Trigger test traffic generation every 5 minutes"
  schedule_expression = "rate(5 minutes)"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-test-traffic-rule-${local.name_suffix}"
  })
}

# EventBridge target for test traffic generation
resource "aws_cloudwatch_event_target" "test_traffic" {
  count = var.test_traffic_generation ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.test_traffic[0].name
  target_id = "TestTrafficGeneratorTarget"
  arn       = aws_lambda_function.test_generator[0].arn
}

# Permission for EventBridge to invoke test generator Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.test_traffic_generation ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_generator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.test_traffic[0].arn
}