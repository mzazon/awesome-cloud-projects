# Main Terraform configuration for IoT Device Management with AWS IoT Core
# This configuration creates a complete IoT infrastructure including device registry,
# certificate management, rules engine, and Lambda processing

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

# ============================================================================
# IoT Thing Type and Device Registry
# ============================================================================

# Create IoT Thing Type for device categorization
resource "aws_iot_thing_type" "temperature_sensor" {
  name = var.iot_thing_type_name

  thing_type_properties {
    description = "Temperature sensor devices for production monitoring"
  }

  tags = local.common_tags
}

# Create IoT Thing (represents a physical device)
resource "aws_iot_thing" "temperature_sensor" {
  name           = "${var.project_name}-sensor-${local.resource_suffix}"
  thing_type_name = aws_iot_thing_type.temperature_sensor.name
  
  attributes = var.device_attributes

  depends_on = [aws_iot_thing_type.temperature_sensor]
}

# ============================================================================
# Certificate Management
# ============================================================================

# Generate device certificate and private key
resource "aws_iot_certificate" "device_cert" {
  active = true

  tags = local.common_tags
}

# Create IoT Policy for device permissions with least privilege
resource "aws_iot_policy" "device_policy" {
  name = "${var.project_name}-device-policy-${local.resource_suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish"
        ]
        Resource = [
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}",
          "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/sensor/temperature/$${iot:Connection.Thing.ThingName}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:GetThingShadow",
          "iot:UpdateThingShadow"
        ]
        Resource = "arn:aws:iot:${var.aws_region}:${data.aws_caller_identity.current.account_id}:thing/$${iot:Connection.Thing.ThingName}"
        Condition = {
          Bool = {
            "iot:Connection.Thing.IsAttached" = "true"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach IoT Policy to certificate
resource "aws_iot_policy_attachment" "device_policy_attachment" {
  policy = aws_iot_policy.device_policy.name
  target = aws_iot_certificate.device_cert.arn
}

# Attach certificate to IoT Thing
resource "aws_iot_thing_principal_attachment" "device_cert_attachment" {
  thing     = aws_iot_thing.temperature_sensor.name
  principal = aws_iot_certificate.device_cert.arn

  depends_on = [aws_iot_policy_attachment.device_policy_attachment]
}

# ============================================================================
# Lambda Function for Data Processing
# ============================================================================

# Create Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"

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

# CloudWatch Logs group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-data-processor-${local.resource_suffix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      temperature_threshold = var.temperature_threshold
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for processing IoT data
resource "aws_lambda_function" "iot_data_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-data-processor-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TEMPERATURE_THRESHOLD = var.temperature_threshold
      ENVIRONMENT          = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# ============================================================================
# IoT Rules Engine
# ============================================================================

# IAM role for IoT Rule to invoke Lambda
resource "aws_iam_role" "iot_rule_role" {
  name = "${var.project_name}-iot-rule-role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for IoT Rule to invoke Lambda
resource "aws_iam_role_policy" "iot_rule_lambda_policy" {
  name = "${var.project_name}-iot-rule-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.iot_rule_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.iot_data_processor.arn
      }
    ]
  })
}

# Lambda permission for IoT to invoke the function
resource "aws_lambda_permission" "iot_lambda_permission" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iot_data_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.sensor_data_rule.arn
}

# IoT Topic Rule for routing sensor data to Lambda
resource "aws_iot_topic_rule" "sensor_data_rule" {
  name        = "${var.project_name}_sensor_data_rule_${local.resource_suffix}"
  description = "Route temperature sensor data to Lambda for processing"
  enabled     = true
  sql         = "SELECT *, topic(3) as device FROM 'sensor/temperature/+'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.iot_data_processor.arn
  }

  depends_on = [aws_iam_role_policy.iot_rule_lambda_policy]

  tags = local.common_tags
}

# ============================================================================
# Device Shadow (Optional)
# ============================================================================

# Initialize device shadow with default state (using AWS CLI in null_resource)
resource "null_resource" "device_shadow_init" {
  count = var.enable_device_shadow ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws iot-data update-thing-shadow \
        --region ${var.aws_region} \
        --thing-name ${aws_iot_thing.temperature_sensor.name} \
        --payload '{
          "state": {
            "desired": {
              "temperature_threshold": ${var.temperature_threshold},
              "reporting_interval": ${var.reporting_interval},
              "active": true
            },
            "reported": {
              "temperature": 22.5,
              "battery_level": 95,
              "firmware_version": "1.0.0"
            }
          }
        }' \
        /tmp/shadow_output.json
    EOT
  }

  depends_on = [
    aws_iot_thing.temperature_sensor,
    aws_iot_thing_principal_attachment.device_cert_attachment
  ]

  triggers = {
    thing_name            = aws_iot_thing.temperature_sensor.name
    temperature_threshold = var.temperature_threshold
    reporting_interval    = var.reporting_interval
  }
}

# ============================================================================
# CloudWatch Dashboard (Optional)
# ============================================================================

# CloudWatch Dashboard for IoT monitoring
resource "aws_cloudwatch_dashboard" "iot_dashboard" {
  dashboard_name = "${var.project_name}-iot-dashboard-${local.resource_suffix}"

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
            ["AWS/IoT", "PublishIn.Success"],
            [".", "Connect.Success"],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.iot_data_processor.function_name],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "IoT Core and Lambda Metrics"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-lambda-errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  insufficient_data_actions = []

  dimensions = {
    FunctionName = aws_lambda_function.iot_data_processor.function_name
  }

  tags = local.common_tags
}