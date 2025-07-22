# Main Terraform configuration for sustainable manufacturing monitoring

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_suffix = random_id.suffix.hex
  carbon_intensity_factor = lookup(var.carbon_intensity_factors, var.aws_region, 0.4)
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ==============================================================================
# IoT SiteWise Asset Model and Assets
# ==============================================================================

# IoT SiteWise Asset Model for manufacturing equipment
resource "aws_iotsitewise_asset_model" "sustainable_manufacturing" {
  name        = var.asset_model_name
  description = "Asset model for sustainable manufacturing monitoring and carbon emissions tracking"

  # Equipment Serial Number - Attribute
  asset_model_property {
    name      = "Equipment_Serial_Number"
    data_type = "STRING"
    type {
      attribute {
        default_value = "UNKNOWN"
      }
    }
  }

  # Power Consumption - Measurement
  asset_model_property {
    name      = "Power_Consumption_kW"
    data_type = "DOUBLE"
    unit      = "kW"
    type {
      measurement {}
    }
  }

  # Production Rate - Measurement
  asset_model_property {
    name      = "Production_Rate_Units_Hour"
    data_type = "DOUBLE"
    unit      = "units/hour"
    type {
      measurement {}
    }
  }

  # Energy Efficiency Ratio - Transform (calculated)
  asset_model_property {
    name      = "Energy_Efficiency_Ratio"
    data_type = "DOUBLE"
    unit      = "units/kWh"
    type {
      transform {
        expression = "production_rate / power_consumption"
        variables {
          name = "production_rate"
          value {
            property_id = aws_iotsitewise_asset_model.sustainable_manufacturing.asset_model_property[2].id
          }
        }
        variables {
          name = "power_consumption"
          value {
            property_id = aws_iotsitewise_asset_model.sustainable_manufacturing.asset_model_property[1].id
          }
        }
      }
    }
  }

  # Total Energy Consumption - Metric (aggregated)
  asset_model_property {
    name      = "Total_Energy_Consumption_kWh"
    data_type = "DOUBLE"
    unit      = "kWh"
    type {
      metric {
        expression = "sum(power)"
        variables {
          name = "power"
          value {
            property_id = aws_iotsitewise_asset_model.sustainable_manufacturing.asset_model_property[1].id
          }
        }
        window {
          tumbling {
            interval = "1h"
          }
        }
      }
    }
  }

  tags = local.common_tags
}

# Manufacturing equipment assets
resource "aws_iotsitewise_asset" "manufacturing_equipment" {
  for_each = var.manufacturing_assets

  name           = each.value.name
  asset_model_id = aws_iotsitewise_asset_model.sustainable_manufacturing.id

  tags = merge(local.common_tags, {
    Name        = each.value.name
    Description = each.value.description
  })

  depends_on = [aws_iotsitewise_asset_model.sustainable_manufacturing]
}

# ==============================================================================
# Lambda Function for Carbon Emissions Calculation
# ==============================================================================

# Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/carbon_calculator.py"
  content  = templatefile("${path.module}/templates/carbon_calculator.py.tpl", {
    carbon_intensity_factors = var.carbon_intensity_factors
  })
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/carbon_calculator.zip"
  depends_on  = [local_file.lambda_source]
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-carbon-calculator-${local.resource_suffix}"

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

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-carbon-calculator-policy-${local.resource_suffix}"
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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "iotsitewise:DescribeAsset",
          "iotsitewise:GetAssetPropertyValue",
          "iotsitewise:GetAssetPropertyValueHistory",
          "iotsitewise:ListAssets",
          "iotsitewise:ListAssociatedAssets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "carbon_calculator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-carbon-calculator-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "carbon_calculator.lambda_handler"
  runtime         = var.lambda_function_config.runtime
  timeout         = var.lambda_function_config.timeout
  memory_size     = var.lambda_function_config.memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CARBON_INTENSITY_FACTOR = local.carbon_intensity_factor
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-carbon-calculator-${local.resource_suffix}"
  retention_in_days = 7
  tags              = local.common_tags
}

# ==============================================================================
# CloudWatch Alarms for Sustainability Monitoring
# ==============================================================================

# Alarm for high carbon emissions
resource "aws_cloudwatch_metric_alarm" "high_carbon_emissions" {
  alarm_name          = "${var.project_name}-high-carbon-emissions-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.sustainability_thresholds.evaluation_periods
  metric_name         = "CarbonEmissions"
  namespace           = "Manufacturing/Sustainability"
  period              = var.sustainability_thresholds.alarm_period
  statistic           = "Average"
  threshold           = var.sustainability_thresholds.high_carbon_emissions_threshold
  alarm_description   = "This metric monitors carbon emissions and alerts when threshold is exceeded"
  alarm_actions       = []

  tags = local.common_tags
}

# Alarm for high power consumption
resource "aws_cloudwatch_metric_alarm" "high_power_consumption" {
  alarm_name          = "${var.project_name}-high-power-consumption-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.sustainability_thresholds.evaluation_periods + 1
  metric_name         = "PowerConsumption"
  namespace           = "Manufacturing/Sustainability"
  period              = var.sustainability_thresholds.alarm_period
  statistic           = "Average"
  threshold           = var.sustainability_thresholds.high_power_consumption_threshold
  alarm_description   = "This metric monitors power consumption and alerts when efficiency drops"
  alarm_actions       = []

  tags = local.common_tags
}

# ==============================================================================
# EventBridge Rule for Automated Reporting
# ==============================================================================

# EventBridge rule for daily sustainability reporting
resource "aws_cloudwatch_event_rule" "daily_sustainability_report" {
  name                = "${var.project_name}-daily-sustainability-report-${local.resource_suffix}"
  description         = "Trigger daily sustainability calculations and reporting"
  schedule_expression = var.reporting_schedule

  tags = local.common_tags
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_sustainability_report.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.carbon_calculator.arn

  input = jsonencode({
    source      = "eventbridge"
    detail-type = "scheduled-report"
    detail = {
      asset_ids = [for asset in aws_iotsitewise_asset.manufacturing_equipment : asset.id]
    }
  })
}

# Permission for EventBridge to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.carbon_calculator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_sustainability_report.arn
}

# ==============================================================================
# CloudWatch Dashboard for Sustainability Monitoring
# ==============================================================================

# CloudWatch Dashboard for sustainability metrics
resource "aws_cloudwatch_dashboard" "sustainability_dashboard" {
  dashboard_name = "${var.project_name}-sustainability-dashboard-${local.resource_suffix}"

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
            ["Manufacturing/Sustainability", "CarbonEmissions"],
            ["Manufacturing/Sustainability", "PowerConsumption"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Carbon Emissions and Power Consumption Trends"
          period  = 300
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
            ["Manufacturing/Sustainability", "CarbonEmissions"]
          ]
          view    = "singleValue"
          region  = var.aws_region
          title   = "Current Carbon Emissions (kg CO2/hr)"
          period  = 300
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
            ["Manufacturing/Sustainability", "PowerConsumption"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Power Consumption by Asset"
          period  = 300
        }
      }
    ]
  })

  tags = local.common_tags
}

# ==============================================================================
# Templates Directory (for Lambda function code)
# ==============================================================================

# Create templates directory for Lambda function
resource "local_file" "lambda_template" {
  filename = "${path.module}/templates/carbon_calculator.py.tpl"
  content  = <<-EOF
import json
import boto3
import datetime
from decimal import Decimal

# Carbon intensity factors (kg CO2 per kWh) by region
CARBON_INTENSITY_FACTORS = ${jsonencode(var.carbon_intensity_factors)}

def lambda_handler(event, context):
    """
    Lambda function to calculate carbon emissions from manufacturing equipment
    """
    sitewise = boto3.client('iotsitewise')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Handle different event sources
        if event.get('source') == 'eventbridge':
            # Scheduled report - process all assets
            asset_ids = event.get('detail', {}).get('asset_ids', [])
            results = []
            
            for asset_id in asset_ids:
                result = process_asset_emissions(sitewise, cloudwatch, asset_id, context)
                results.append(result)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Daily sustainability report processed',
                    'results': results
                })
            }
        else:
            # Direct invocation - process single asset
            asset_id = event.get('asset_id')
            if not asset_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps('Asset ID required')
                }
            
            result = process_asset_emissions(sitewise, cloudwatch, asset_id, context)
            return {
                'statusCode': 200,
                'body': json.dumps(result)
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_asset_emissions(sitewise, cloudwatch, asset_id, context):
    """
    Process carbon emissions for a single asset
    """
    try:
        # Get asset properties
        asset_properties = sitewise.describe_asset(assetId=asset_id)
        
        # Find Power_Consumption_kW property ID
        power_property_id = None
        for prop in asset_properties['assetProperties']:
            if prop['name'] == 'Power_Consumption_kW':
                power_property_id = prop['id']
                break
        
        if not power_property_id:
            return {
                'asset_id': asset_id,
                'error': 'Power consumption property not found'
            }
        
        # Get latest power consumption value
        response = sitewise.get_asset_property_value(
            assetId=asset_id,
            propertyId=power_property_id
        )
        
        power_consumption = response['propertyValue']['value']['doubleValue']
        
        # Calculate carbon emissions
        region = context.invoked_function_arn.split(':')[3]
        carbon_factor = CARBON_INTENSITY_FACTORS.get(region, 0.4)
        carbon_emissions = power_consumption * carbon_factor
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Manufacturing/Sustainability',
            MetricData=[
                {
                    'MetricName': 'CarbonEmissions',
                    'Dimensions': [
                        {
                            'Name': 'AssetId',
                            'Value': asset_id
                        }
                    ],
                    'Value': carbon_emissions,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.utcnow()
                },
                {
                    'MetricName': 'PowerConsumption',
                    'Dimensions': [
                        {
                            'Name': 'AssetId',
                            'Value': asset_id
                        }
                    ],
                    'Value': power_consumption,
                    'Unit': 'None',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
        
        return {
            'asset_id': asset_id,
            'carbon_emissions_kg_co2_per_hour': carbon_emissions,
            'power_consumption_kw': power_consumption,
            'carbon_intensity_factor': carbon_factor,
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        return {
            'asset_id': asset_id,
            'error': str(e)
        }
EOF
}