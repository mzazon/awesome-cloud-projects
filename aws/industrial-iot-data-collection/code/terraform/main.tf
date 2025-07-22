# Data sources for account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

#===============================================================================
# IoT SiteWise Resources
#===============================================================================

# IoT SiteWise Asset Model - Defines the structure for manufacturing equipment
resource "aws_iotsitewise_asset_model" "production_line_equipment" {
  name        = var.asset_model_name
  description = var.asset_model_description

  # Temperature measurement property
  property {
    name      = "Temperature"
    data_type = "DOUBLE"
    unit      = "Celsius"
    type {
      measurement {}
    }
  }

  # Pressure measurement property
  property {
    name      = "Pressure"
    data_type = "DOUBLE"
    unit      = "PSI"
    type {
      measurement {}
    }
  }

  # Operational efficiency transform property (calculated from temperature and pressure)
  property {
    name      = "OperationalEfficiency"
    data_type = "DOUBLE"
    unit      = "Percent"
    type {
      transform {
        expression = "temp / 100 * pressure / 50"
        variables {
          name = "temp"
          value {
            property_id = aws_iotsitewise_asset_model.production_line_equipment.property[0].id
          }
        }
        variables {
          name = "pressure"
          value {
            property_id = aws_iotsitewise_asset_model.production_line_equipment.property[1].id
          }
        }
      }
    }
  }

  tags = local.common_tags
}

# IoT SiteWise Asset - Represents the physical equipment instance
resource "aws_iotsitewise_asset" "production_line_pump" {
  name           = var.asset_name
  asset_model_id = aws_iotsitewise_asset_model.production_line_equipment.id

  tags = local.common_tags

  # Ensure asset model is active before creating asset
  depends_on = [aws_iotsitewise_asset_model.production_line_equipment]
}

# Data source to get asset properties after creation
data "aws_iotsitewise_asset" "production_line_pump_data" {
  asset_id = aws_iotsitewise_asset.production_line_pump.id

  depends_on = [aws_iotsitewise_asset.production_line_pump]
}

# IoT SiteWise Gateway - Manages data collection from industrial equipment
resource "aws_iotsitewise_gateway" "manufacturing_gateway" {
  name = "${var.gateway_name}-${random_string.suffix.result}"

  # Gateway platform configuration for Greengrass
  platform {
    greengrass {
      group_arn = "arn:aws:greengrass:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:groups/simulation-group"
    }
  }

  tags = local.common_tags
}

#===============================================================================
# Amazon Timestream Resources
#===============================================================================

# Timestream Database - Purpose-built for time-series data
resource "aws_timestreamwrite_database" "industrial_data" {
  database_name = "${var.timestream_database_name}-${random_string.suffix.result}"

  tags = local.common_tags
}

# Timestream Table - Stores industrial equipment metrics
resource "aws_timestreamwrite_table" "equipment_metrics" {
  database_name = aws_timestreamwrite_database.industrial_data.database_name
  table_name    = var.timestream_table_name

  # Data retention configuration
  retention_properties {
    memory_store_retention_period_in_hours   = var.timestream_memory_retention_hours
    magnetic_store_retention_period_in_days = var.timestream_magnetic_retention_days
  }

  tags = local.common_tags
}

#===============================================================================
# CloudWatch Resources
#===============================================================================

# CloudWatch Alarm for high temperature monitoring
resource "aws_cloudwatch_metric_alarm" "high_temperature" {
  alarm_name          = "${local.name_prefix}-high-temperature"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Temperature"
  namespace           = "AWS/IoTSiteWise"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.temperature_alarm_threshold
  alarm_description   = "Alert when equipment temperature exceeds threshold"
  alarm_actions = var.create_sns_topic ? [aws_sns_topic.equipment_alerts[0].arn] : []

  # Dimensions for the specific asset
  dimensions = {
    AssetId = aws_iotsitewise_asset.production_line_pump.id
  }

  tags = local.common_tags
}

# CloudWatch Log Group for IoT SiteWise logging
resource "aws_cloudwatch_log_group" "sitewise_logs" {
  name              = "/aws/iotsitewise/${local.name_prefix}"
  retention_in_days = 14

  tags = local.common_tags
}

#===============================================================================
# SNS Resources
#===============================================================================

# SNS Topic for equipment alerts (conditional creation)
resource "aws_sns_topic" "equipment_alerts" {
  count = var.create_sns_topic ? 1 : 0

  name = "${var.sns_topic_name}-${random_string.suffix.result}"

  tags = local.common_tags
}

# SNS Topic Policy for CloudWatch alarms
resource "aws_sns_topic_policy" "equipment_alerts_policy" {
  count = var.create_sns_topic ? 1 : 0

  arn = aws_sns_topic.equipment_alerts[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.equipment_alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS Topic Subscription for email notifications (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.create_sns_topic && var.email_notification_endpoint != "" ? 1 : 0

  topic_arn = aws_sns_topic.equipment_alerts[0].arn
  protocol  = "email"
  endpoint  = var.email_notification_endpoint
}

#===============================================================================
# IAM Resources
#===============================================================================

# IAM Role for IoT SiteWise service
resource "aws_iam_role" "sitewise_service_role" {
  name = "${local.name_prefix}-sitewise-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iotsitewise.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for IoT SiteWise to access Timestream
resource "aws_iam_role_policy" "sitewise_timestream_policy" {
  name = "${local.name_prefix}-sitewise-timestream-policy"
  role = aws_iam_role.sitewise_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeTable",
          "timestream:DescribeDatabase"
        ]
        Resource = [
          aws_timestreamwrite_database.industrial_data.arn,
          aws_timestreamwrite_table.equipment_metrics.arn
        ]
      }
    ]
  })
}

# IAM Policy for IoT SiteWise to write to CloudWatch
resource "aws_iam_role_policy" "sitewise_cloudwatch_policy" {
  name = "${local.name_prefix}-sitewise-cloudwatch-policy"
  role = aws_iam_role.sitewise_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

#===============================================================================
# Sample Data Ingestion (Optional - for demonstration)
#===============================================================================

# Lambda function for sample data ingestion (optional)
resource "aws_lambda_function" "sample_data_ingestion" {
  filename         = "sample_data_ingestion.zip"
  function_name    = "${local.name_prefix}-sample-data-ingestion"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  # Create a simple Lambda deployment package
  depends_on = [data.archive_file.sample_data_ingestion_zip]

  environment {
    variables = {
      ASSET_ID              = aws_iotsitewise_asset.production_line_pump.id
      TEMPERATURE_PROPERTY_ID = data.aws_iotsitewise_asset.production_line_pump_data.asset_properties[0].id
      PRESSURE_PROPERTY_ID   = data.aws_iotsitewise_asset.production_line_pump_data.asset_properties[1].id
    }
  }

  tags = local.common_tags
}

# Create Lambda deployment package
data "archive_file" "sample_data_ingestion_zip" {
  type        = "zip"
  output_path = "sample_data_ingestion.zip"
  
  source {
    content = <<EOF
import json
import boto3
import random
import time
from datetime import datetime

def handler(event, context):
    sitewise = boto3.client('iotsitewise')
    
    # Generate sample data
    temperature = round(random.uniform(70.0, 85.0), 2)
    pressure = round(random.uniform(40.0, 50.0), 2)
    
    # Prepare batch put request
    entries = [
        {
            'entryId': f'temp-{int(time.time())}',
            'assetId': os.environ['ASSET_ID'],
            'propertyId': os.environ['TEMPERATURE_PROPERTY_ID'],
            'propertyValues': [
                {
                    'value': {'doubleValue': temperature},
                    'timestamp': {'timeInSeconds': int(time.time())}
                }
            ]
        },
        {
            'entryId': f'pressure-{int(time.time())}',
            'assetId': os.environ['ASSET_ID'],
            'propertyId': os.environ['PRESSURE_PROPERTY_ID'],
            'propertyValues': [
                {
                    'value': {'doubleValue': pressure},
                    'timestamp': {'timeInSeconds': int(time.time())}
                }
            ]
        }
    ]
    
    # Send data to IoT SiteWise
    response = sitewise.batch_put_asset_property_value(entries=entries)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Sample data ingested successfully',
            'temperature': temperature,
            'pressure': pressure,
            'response': response
        })
    }
EOF
    filename = "index.py"
  }
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role"

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

# IAM Policy for Lambda to write to IoT SiteWise
resource "aws_iam_role_policy" "lambda_sitewise_policy" {
  name = "${local.name_prefix}-lambda-sitewise-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iotsitewise:BatchPutAssetPropertyValue",
          "iotsitewise:GetAssetPropertyValue",
          "iotsitewise:DescribeAsset"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# EventBridge rule for periodic data ingestion (optional)
resource "aws_cloudwatch_event_rule" "sample_data_schedule" {
  name        = "${local.name_prefix}-sample-data-schedule"
  description = "Schedule for sample data ingestion"
  
  # Run every 5 minutes (adjust as needed)
  schedule_expression = "rate(5 minutes)"
  
  tags = local.common_tags
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.sample_data_schedule.name
  target_id = "SampleDataIngestionTarget"
  arn       = aws_lambda_function.sample_data_ingestion.arn
}

# Lambda permission for EventBridge to invoke the function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sample_data_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sample_data_schedule.arn
}