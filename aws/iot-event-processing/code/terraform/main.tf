# main.tf - Main Terraform configuration for AWS IoT Rules Engine Event Processing

# Generate random suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  name_prefix      = "factory-iot-${random_id.suffix.hex}"
  common_tags = {
    Project     = "IoTRulesEngine"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Data sources for current AWS configuration
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# DynamoDB Table for telemetry data storage
resource "aws_dynamodb_table" "telemetry_table" {
  name           = "${local.name_prefix}-telemetry"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "deviceId"
  range_key      = "timestamp"

  attribute {
    name = "deviceId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts_topic" {
  name         = "${local.name_prefix}-alerts"
  display_name = "Factory Alerts"

  tags = local.common_tags
}

# CloudWatch Log Group for IoT Rules Engine
resource "aws_cloudwatch_log_group" "iot_rules_logs" {
  name              = "/aws/iot/rules"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# IAM Role for IoT Rules Engine
resource "aws_iam_role" "iot_rules_role" {
  name = "${local.name_prefix}-rules-role"

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

# IAM Policy for IoT Rules Engine
resource "aws_iam_policy" "iot_rules_policy" {
  name        = "${local.name_prefix}-rules-policy"
  description = "Policy for IoT Rules Engine to access DynamoDB, SNS, and Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.telemetry_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts_topic.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.event_processor.arn
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "iot_rules_policy_attachment" {
  role       = aws_iam_role.iot_rules_role.name
  policy_arn = aws_iam_policy.iot_rules_policy.arn
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role"

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

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for event processing
resource "aws_lambda_function" "event_processor" {
  filename         = "lambda_function.zip"
  function_name    = "${local.name_prefix}-event-processor"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-event-processor"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content = <<EOF
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Process IoT events and perform custom business logic
    """
    try:
        # Parse the incoming IoT message
        device_id = event.get('deviceId', 'unknown')
        temperature = event.get('temperature', 0)
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        
        # Custom processing logic
        severity = 'normal'
        if temperature > 85:
            severity = 'critical'
        elif temperature > 75:
            severity = 'warning'
        
        # Log the processed event
        print(f"Processing event from {device_id}: temp={temperature}°C, severity={severity}")
        
        # Return enriched data
        return {
            'statusCode': 200,
            'body': json.dumps({
                'deviceId': device_id,
                'temperature': temperature,
                'severity': severity,
                'processedAt': timestamp,
                'message': f'Temperature {temperature}°C processed with severity {severity}'
            })
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "lambda_function.py"
  }
}

# Grant IoT permission to invoke Lambda
resource "aws_lambda_permission" "allow_iot_invoke" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.motor_status_rule.arn
}

# IAM Role for CloudWatch Logging
resource "aws_iam_role" "iot_cloudwatch_role" {
  name = "${local.name_prefix}-cloudwatch-role"

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

# Attach CloudWatch logs policy for IoT
resource "aws_iam_role_policy_attachment" "iot_cloudwatch_logs" {
  role       = aws_iam_role.iot_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTLogsRole"
}

# IoT Topic Rules for event processing

# Temperature Alert Rule
resource "aws_iot_topic_rule" "temperature_alert_rule" {
  name        = "TemperatureAlertRule"
  enabled     = true
  description = "Monitor temperature sensors and trigger alerts for high temperatures"
  sql         = "SELECT deviceId, temperature, timestamp() as timestamp FROM 'factory/temperature' WHERE temperature > ${var.temperature_threshold}"
  sql_version = "2016-03-23"

  # DynamoDB action
  dynamodb {
    table_name = aws_dynamodb_table.telemetry_table.name
    role_arn   = aws_iam_role.iot_rules_role.arn
    hash_key_field  = "deviceId"
    hash_key_value  = "$${deviceId}"
    range_key_field = "timestamp"
    range_key_value = "$${timestamp}"
    payload_field   = "data"
  }

  # SNS action
  sns {
    role_arn = aws_iam_role.iot_rules_role.arn
    target_arn = aws_sns_topic.alerts_topic.arn
    message_format = "JSON"
  }

  tags = local.common_tags
}

# Motor Status Rule
resource "aws_iot_topic_rule" "motor_status_rule" {
  name        = "MotorStatusRule"
  enabled     = true
  description = "Monitor motor controllers for errors and excessive vibration"
  sql         = "SELECT deviceId, motorStatus, vibration, timestamp() as timestamp FROM 'factory/motors' WHERE motorStatus = 'error' OR vibration > ${var.vibration_threshold}"
  sql_version = "2016-03-23"

  # DynamoDB action
  dynamodb {
    table_name = aws_dynamodb_table.telemetry_table.name
    role_arn   = aws_iam_role.iot_rules_role.arn
    hash_key_field  = "deviceId"
    hash_key_value  = "$${deviceId}"
    range_key_field = "timestamp"
    range_key_value = "$${timestamp}"
    payload_field   = "data"
  }

  # Lambda action
  lambda {
    function_arn = aws_lambda_function.event_processor.arn
  }

  tags = local.common_tags
}

# Security Event Rule
resource "aws_iot_topic_rule" "security_event_rule" {
  name        = "SecurityEventRule"
  enabled     = true
  description = "Process security events and trigger immediate alerts"
  sql         = "SELECT deviceId, eventType, severity, location, timestamp() as timestamp FROM 'factory/security' WHERE eventType IN ('intrusion', 'unauthorized_access', 'door_breach')"
  sql_version = "2016-03-23"

  # SNS action
  sns {
    role_arn = aws_iam_role.iot_rules_role.arn
    target_arn = aws_sns_topic.alerts_topic.arn
    message_format = "JSON"
  }

  # DynamoDB action
  dynamodb {
    table_name = aws_dynamodb_table.telemetry_table.name
    role_arn   = aws_iam_role.iot_rules_role.arn
    hash_key_field  = "deviceId"
    hash_key_value  = "$${deviceId}"
    range_key_field = "timestamp"
    range_key_value = "$${timestamp}"
    payload_field   = "data"
  }

  tags = local.common_tags
}

# Data Archival Rule
resource "aws_iot_topic_rule" "data_archival_rule" {
  name        = "DataArchivalRule"
  enabled     = var.enable_data_archival
  description = "Archive all factory data every 5 minutes for historical analysis"
  sql         = "SELECT * FROM 'factory/+' WHERE timestamp() % 300 = 0"
  sql_version = "2016-03-23"

  # DynamoDB action
  dynamodb {
    table_name = aws_dynamodb_table.telemetry_table.name
    role_arn   = aws_iam_role.iot_rules_role.arn
    hash_key_field  = "deviceId"
    hash_key_value  = "$${deviceId}"
    range_key_field = "timestamp"
    range_key_value = "$${timestamp}"
    payload_field   = "data"
  }

  tags = local.common_tags
}

# Optional: Create an SNS subscription for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Optional: Create IoT Thing for testing
resource "aws_iot_thing" "test_sensor" {
  count = var.create_test_thing ? 1 : 0
  name  = "${local.name_prefix}-sensor"

  attributes = {
    location = "production-floor"
    type     = "temperature-sensor"
  }

  thing_type_name = aws_iot_thing_type.sensor_type[0].name
}

# Optional: IoT Thing Type for sensors
resource "aws_iot_thing_type" "sensor_type" {
  count = var.create_test_thing ? 1 : 0
  name  = "${local.name_prefix}-sensor-type"

  properties {
    description = "Factory sensor device type"
    searchable_attributes = ["location", "type"]
  }
}

# Optional: IoT Policy for device authentication
resource "aws_iot_policy" "device_policy" {
  count = var.create_test_thing ? 1 : 0
  name  = "${local.name_prefix}-device-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Publish"
        ]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/factory/*"
        ]
      }
    ]
  })
}