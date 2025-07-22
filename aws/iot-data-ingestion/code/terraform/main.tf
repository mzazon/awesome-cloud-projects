# main.tf - Main infrastructure for IoT data ingestion pipeline

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix = random_id.suffix.hex
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "iot-data-ingestion-aws-iot-core"
    },
    var.additional_tags
  )
}

# ============================================================================
# IoT Core Resources
# ============================================================================

# IoT Thing Type for categorizing devices
resource "aws_iot_thing_type" "sensor_device" {
  name = var.iot_thing_type_name

  thing_type_properties {
    description = "IoT Thing Type for sensor devices in data ingestion pipeline"
  }

  tags = local.common_tags
}

# IoT Thing (represents a physical device)
resource "aws_iot_thing" "sensor_device" {
  name           = "${var.project_name}-sensor-${local.suffix}"
  thing_type_name = aws_iot_thing_type.sensor_device.name

  attributes = {
    deviceType = "sensor"
    location   = "sensor-room-1"
  }

  tags = local.common_tags
}

# IoT Certificate for device authentication (if enabled)
resource "aws_iot_certificate" "device_cert" {
  count  = var.create_test_certificates ? 1 : 0
  active = true

  tags = local.common_tags
}

# IoT Policy defining device permissions
resource "aws_iot_policy" "sensor_policy" {
  name = "${var.project_name}-sensor-policy-${local.suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/${aws_iot_thing.sensor_device.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = [
          for topic in var.allowed_iot_topics :
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${topic}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = [
          for topic in var.allowed_iot_topics :
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/${topic}"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to certificate (if certificates are created)
resource "aws_iot_policy_attachment" "sensor_policy_attachment" {
  count  = var.create_test_certificates ? 1 : 0
  policy = aws_iot_policy.sensor_policy.name
  target = aws_iot_certificate.device_cert[0].arn
}

# Attach certificate to thing (if certificates are created)
resource "aws_iot_thing_principal_attachment" "sensor_cert_attachment" {
  count     = var.create_test_certificates ? 1 : 0
  thing     = aws_iot_thing.sensor_device.name
  principal = aws_iot_certificate.device_cert[0].arn
}

# ============================================================================
# DynamoDB Table for Sensor Data Storage
# ============================================================================

# KMS key for DynamoDB encryption
resource "aws_kms_key" "dynamodb_key" {
  description = "KMS key for DynamoDB table encryption"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "dynamodb_key_alias" {
  name          = "alias/${var.project_name}-dynamodb-${local.suffix}"
  target_key_id = aws_kms_key.dynamodb_key.key_id
}

# DynamoDB table for storing sensor data
resource "aws_dynamodb_table" "sensor_data" {
  name           = "${var.project_name}-sensor-data-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
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

  # Global Secondary Index for querying by timestamp across all devices
  global_secondary_index {
    name            = "TimestampIndex"
    hash_key        = "timestamp"
    projection_type = "ALL"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }

  tags = local.common_tags
}

# ============================================================================
# SNS Topic for Alerts
# ============================================================================

# KMS key for SNS encryption
resource "aws_kms_key" "sns_key" {
  description = "KMS key for SNS topic encryption"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SNS service"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "sns_key_alias" {
  name          = "alias/${var.project_name}-sns-${local.suffix}"
  target_key_id = aws_kms_key.sns_key.key_id
}

# SNS topic for temperature alerts
resource "aws_sns_topic" "iot_alerts" {
  name              = "${var.project_name}-iot-alerts-${local.suffix}"
  kms_master_key_id = aws_kms_key.sns_key.arn

  tags = local.common_tags
}

# SNS email subscription (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.sns_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.iot_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# ============================================================================
# Lambda Function for Data Processing
# ============================================================================

# KMS key for Lambda environment variables encryption
resource "aws_kms_key" "lambda_key" {
  description = "KMS key for Lambda environment variables encryption"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "lambda_key_alias" {
  name          = "alias/${var.project_name}-lambda-${local.suffix}"
  target_key_id = aws_kms_key.lambda_key.key_id
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.suffix}"

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

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${local.suffix}"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-iot-processor-${local.suffix}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.sensor_data.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.iot_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.dynamodb_key.arn,
          aws_kms_key.sns_key.arn,
          aws_kms_key.lambda_key.arn
        ]
      }
    ]
  })
}

# Lambda function code
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda_function.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    temperature_threshold = var.temperature_threshold
  })
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/iot-processor.zip"
  depends_on  = [local_file.lambda_code]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-iot-processor-${local.suffix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_cloudwatch_logs_encryption ? aws_kms_key.lambda_key.arn : null

  tags = local.common_tags
}

# Lambda function
resource "aws_lambda_function" "iot_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-iot-processor-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.sensor_data.name
      SNS_TOPIC_ARN     = aws_sns_topic.iot_alerts.arn
      TEMP_THRESHOLD    = tostring(var.temperature_threshold)
    }
  }

  kms_key_arn = aws_kms_key.lambda_key.arn

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# Create Lambda function source file
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py.tpl"
  content = <<EOF
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse IoT message
        device_id = event.get('deviceId')
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        temperature = event.get('temperature')
        humidity = event.get('humidity')
        location = event.get('location', 'unknown')
        
        logger.info(f"Processing data from device: {device_id}")
        
        # Validate required fields
        if not all([device_id, temperature, humidity]):
            raise ValueError("Missing required fields: deviceId, temperature, or humidity")
        
        # Store data in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        table.put_item(
            Item={
                'deviceId': device_id,
                'timestamp': int(timestamp),
                'temperature': float(temperature),
                'humidity': float(humidity),
                'location': location,
                'processed_at': int(datetime.now().timestamp())
            }
        )
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'Temperature',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id},
                        {'Name': 'Location', 'Value': location}
                    ],
                    'Value': float(temperature),
                    'Unit': 'None'
                },
                {
                    'MetricName': 'Humidity',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id},
                        {'Name': 'Location', 'Value': location}
                    ],
                    'Value': float(humidity),
                    'Unit': 'Percent'
                }
            ]
        )
        
        # Check for temperature alerts
        temp_threshold = float(os.environ.get('TEMP_THRESHOLD', '${temperature_threshold}'))
        if float(temperature) > temp_threshold:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'High Temperature Alert - Device {device_id}',
                Message=f'''High temperature detected!
                
Device ID: {device_id}
Location: {location}
Temperature: {temperature}°C
Threshold: {temp_threshold}°C
Humidity: {humidity}%
Timestamp: {datetime.fromtimestamp(int(timestamp)).isoformat()}

Please investigate immediately.'''
            )
            logger.warning(f"High temperature alert sent for device {device_id}: {temperature}°C")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data processed successfully',
                'deviceId': device_id,
                'timestamp': timestamp,
                'alertSent': float(temperature) > temp_threshold
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        logger.error(f"Event data: {json.dumps(event)}")
        
        # Send error metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        raise
EOF
}

# ============================================================================
# IoT Rules Engine
# ============================================================================

# IAM role for IoT Rule
resource "aws_iam_role" "iot_rule_role" {
  name = "${var.project_name}-iot-rule-role-${local.suffix}"

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

# IoT Rule policy
resource "aws_iam_role_policy" "iot_rule_policy" {
  name = "${var.project_name}-iot-rule-policy-${local.suffix}"
  role = aws_iam_role.iot_rule_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.iot_processor.arn
      }
    ]
  })
}

# IoT Topic Rule to route sensor data to Lambda
resource "aws_iot_topic_rule" "process_sensor_data" {
  name        = "ProcessSensorData${replace(title(local.suffix), "-", "")}"
  description = "Route sensor data to Lambda for processing"
  enabled     = true
  sql         = "SELECT * FROM 'topic/sensor/data'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.iot_processor.arn
  }

  tags = local.common_tags
}

# Lambda permission for IoT to invoke the function
resource "aws_lambda_permission" "iot_invoke_lambda" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iot_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.process_sensor_data.arn
}

# ============================================================================
# CloudWatch Dashboard (Optional)
# ============================================================================

resource "aws_cloudwatch_dashboard" "iot_dashboard" {
  dashboard_name = "${var.project_name}-iot-dashboard-${local.suffix}"

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
            ["IoT/Sensors", "Temperature", "DeviceId", aws_iot_thing.sensor_device.name],
            [".", "Humidity", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "IoT Sensor Metrics"
          period  = 300
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.iot_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
        }
      }
    ]
  })
}

# ============================================================================
# AWS IoT Device Defender (Optional)
# ============================================================================

resource "aws_iot_security_profile" "device_security" {
  count = var.enable_iot_device_defender ? 1 : 0
  name  = "${var.project_name}-security-profile-${local.suffix}"

  behaviors {
    name   = "num-messages-sent"
    metric = "aws:num-messages-sent"
    criteria {
      comparison_operator = "greater-than"
      value {
        count = 100
      }
      duration_seconds = 300
    }
  }

  behaviors {
    name   = "num-authorization-failures"
    metric = "aws:num-authorization-failures"
    criteria {
      comparison_operator = "greater-than"
      value {
        count = 5
      }
      duration_seconds = 300
    }
  }

  alert_targets = {
    SNS = {
      alert_target_arn = aws_sns_topic.iot_alerts.arn
      role_arn        = aws_iam_role.iot_rule_role.arn
    }
  }

  tags = local.common_tags
}

resource "aws_iot_thing_group" "sensor_group" {
  count = var.enable_iot_device_defender ? 1 : 0
  name  = "${var.project_name}-sensor-group-${local.suffix}"

  thing_group_properties {
    description = "Thing group for sensor devices"
  }

  tags = local.common_tags
}

resource "aws_iot_thing_group_membership" "sensor_membership" {
  count            = var.enable_iot_device_defender ? 1 : 0
  thing_name       = aws_iot_thing.sensor_device.name
  thing_group_name = aws_iot_thing_group.sensor_group[0].name
}