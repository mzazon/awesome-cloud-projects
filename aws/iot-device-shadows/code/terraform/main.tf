# IoT Device Shadows State Management Infrastructure

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get IoT Core endpoint
data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
  
  # Resource names
  thing_name        = "smart-thermostat-${local.random_suffix}"
  policy_name       = "SmartThermostatPolicy-${local.random_suffix}"
  rule_name         = "ShadowUpdateRule-${local.random_suffix}"
  lambda_function   = "ProcessShadowUpdate-${local.random_suffix}"
  table_name        = "DeviceStateHistory-${local.random_suffix}"
}

# ============================================================================
# IoT Core Resources
# ============================================================================

# Create IoT Thing Type for categorizing devices
resource "aws_iot_thing_type" "thermostat" {
  name        = var.thing_type_name
  description = "Smart thermostat devices for HVAC control"
  
  properties {
    description = "IoT Thing Type for smart thermostat devices"
    searchable_attributes = ["manufacturer", "model"]
  }
  
  tags = local.common_tags
}

# Create IoT Thing representing the physical device
resource "aws_iot_thing" "smart_thermostat" {
  name           = local.thing_name
  thing_type_name = aws_iot_thing_type.thermostat.name
  
  attributes = var.thing_attributes
  
  depends_on = [aws_iot_thing_type.thermostat]
}

# Generate device certificate and private key
resource "aws_iot_certificate" "device_cert" {
  active = true
  
  lifecycle {
    create_before_destroy = true
  }
}

# Create IoT Policy for device permissions
resource "aws_iot_policy" "device_policy" {
  name = local.policy_name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/things/$${iot:Connection.Thing.ThingName}/shadow/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/things/$${iot:Connection.Thing.ThingName}/shadow/*"
        ]
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policy to certificate
resource "aws_iot_policy_attachment" "device_policy_attachment" {
  policy = aws_iot_policy.device_policy.name
  target = aws_iot_certificate.device_cert.arn
}

# Attach certificate to Thing
resource "aws_iot_thing_principal_attachment" "device_cert_attachment" {
  thing     = aws_iot_thing.smart_thermostat.name
  principal = aws_iot_certificate.device_cert.arn
}

# ============================================================================
# DynamoDB Table for State History
# ============================================================================

# DynamoDB table for storing device state history
resource "aws_dynamodb_table" "device_state_history" {
  name           = local.table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "ThingName"
  range_key      = "Timestamp"
  
  attribute {
    name = "ThingName"
    type = "S"
  }
  
  attribute {
    name = "Timestamp"
    type = "N"
  }
  
  # Enable point-in-time recovery if requested
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = local.table_name
  })
}

# ============================================================================
# Lambda Function for Shadow Processing
# ============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.enable_cloudwatch_logs_retention ? 1 : 0
  
  name              = "/aws/lambda/${local.lambda_function}"
  retention_in_days = var.cloudwatch_logs_retention_days
  
  tags = local.common_tags
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.lambda_function}-role"
  
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

# IAM policy for Lambda execution
resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "${local.lambda_function}-policy"
  description = "IAM policy for Lambda function to process IoT shadow updates"
  
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.device_state_history.arn
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

# Lambda function
resource "aws_lambda_function" "shadow_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.device_state_history.name
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = local.common_tags
}

# ============================================================================
# IoT Rule for Shadow Updates
# ============================================================================

# IAM role for IoT Rule to invoke Lambda
resource "aws_iam_role" "iot_rule_role" {
  name = "${local.rule_name}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for IoT Rule to invoke Lambda
resource "aws_iam_policy" "iot_rule_policy" {
  name        = "${local.rule_name}-policy"
  description = "IAM policy for IoT Rule to invoke Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.shadow_processor.arn
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policy to IoT Rule role
resource "aws_iam_role_policy_attachment" "iot_rule_policy_attachment" {
  role       = aws_iam_role.iot_rule_role.name
  policy_arn = aws_iam_policy.iot_rule_policy.arn
}

# IoT Topic Rule for processing shadow updates
resource "aws_iot_topic_rule" "shadow_update_rule" {
  name        = local.rule_name
  description = "Process Device Shadow updates and trigger Lambda function"
  enabled     = true
  
  sql         = "SELECT * FROM '$aws/things/+/shadow/update/accepted'"
  sql_version = "2016-03-23"
  
  lambda {
    function_arn = aws_lambda_function.shadow_processor.arn
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.iot_rule_policy_attachment
  ]
  
  tags = local.common_tags
}

# Lambda permission for IoT Rule to invoke function
resource "aws_lambda_permission" "allow_iot_invoke" {
  statement_id  = "AllowIoTInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shadow_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.shadow_update_rule.arn
}

# ============================================================================
# Initialize Device Shadow (Optional)
# ============================================================================

# Initialize device shadow with default state
resource "aws_iot_thing_group" "demo_group" {
  name = "${local.name_prefix}-demo-group"
  
  properties {
    description = "Demo group for IoT shadow management"
  }
  
  tags = local.common_tags
}

# Add thing to group
resource "aws_iot_thing_group_membership" "demo_membership" {
  thing_name       = aws_iot_thing.smart_thermostat.name
  thing_group_name = aws_iot_thing_group.demo_group.name
}