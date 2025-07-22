# Outputs for sustainable manufacturing monitoring infrastructure

# ==============================================================================
# IoT SiteWise Outputs
# ==============================================================================

output "asset_model_id" {
  description = "ID of the IoT SiteWise asset model"
  value       = aws_iotsitewise_asset_model.sustainable_manufacturing.id
}

output "asset_model_name" {
  description = "Name of the IoT SiteWise asset model"
  value       = aws_iotsitewise_asset_model.sustainable_manufacturing.name
}

output "asset_model_arn" {
  description = "ARN of the IoT SiteWise asset model"
  value       = aws_iotsitewise_asset_model.sustainable_manufacturing.arn
}

output "manufacturing_assets" {
  description = "Map of manufacturing equipment assets with their IDs and details"
  value = {
    for key, asset in aws_iotsitewise_asset.manufacturing_equipment : key => {
      id   = asset.id
      name = asset.name
      arn  = asset.arn
    }
  }
}

output "manufacturing_asset_ids" {
  description = "List of all manufacturing equipment asset IDs"
  value       = [for asset in aws_iotsitewise_asset.manufacturing_equipment : asset.id]
}

# ==============================================================================
# Lambda Function Outputs
# ==============================================================================

output "lambda_function_name" {
  description = "Name of the carbon calculator Lambda function"
  value       = aws_lambda_function.carbon_calculator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the carbon calculator Lambda function"
  value       = aws_lambda_function.carbon_calculator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the carbon calculator Lambda function"
  value       = aws_lambda_function.carbon_calculator.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ==============================================================================
# CloudWatch Outputs
# ==============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for sustainability metrics"
  value       = aws_cloudwatch_dashboard.sustainability_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.sustainability_dashboard.dashboard_name}"
}

output "carbon_emissions_alarm_name" {
  description = "Name of the high carbon emissions alarm"
  value       = aws_cloudwatch_metric_alarm.high_carbon_emissions.alarm_name
}

output "power_consumption_alarm_name" {
  description = "Name of the high power consumption alarm"
  value       = aws_cloudwatch_metric_alarm.high_power_consumption.alarm_name
}

# ==============================================================================
# EventBridge Outputs
# ==============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for daily sustainability reporting"
  value       = aws_cloudwatch_event_rule.daily_sustainability_report.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for daily sustainability reporting"
  value       = aws_cloudwatch_event_rule.daily_sustainability_report.arn
}

output "reporting_schedule" {
  description = "Schedule expression for automated sustainability reporting"
  value       = var.reporting_schedule
}

# ==============================================================================
# Configuration Outputs
# ==============================================================================

output "carbon_intensity_factor" {
  description = "Carbon intensity factor used for the current region"
  value       = local.carbon_intensity_factor
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource names"
  value       = local.resource_suffix
}

# ==============================================================================
# Quick Start Commands
# ==============================================================================

output "test_lambda_command" {
  description = "AWS CLI command to test the carbon calculator Lambda function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.carbon_calculator.function_name} --payload '{\"asset_id\":\"${values(aws_iotsitewise_asset.manufacturing_equipment)[0].id}\"}' response.json"
}

output "simulate_data_command" {
  description = "Example command to simulate manufacturing data"
  value       = <<-EOT
    aws iotsitewise batch-put-asset-property-value --entries '[
      {
        "entryId": "power-$(date +%s)",
        "assetId": "${values(aws_iotsitewise_asset.manufacturing_equipment)[0].id}",
        "propertyId": "Power_Consumption_kW",
        "propertyValues": [
          {
            "value": {"doubleValue": 75.5},
            "timestamp": {"timeInSeconds": $(date +%s)},
            "quality": "GOOD"
          }
        ]
      }
    ]'
  EOT
}

output "view_metrics_command" {
  description = "AWS CLI command to view sustainability metrics"
  value       = "aws cloudwatch list-metrics --namespace 'Manufacturing/Sustainability'"
}

# ==============================================================================
# Resource Summary
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources for sustainable manufacturing monitoring"
  value = {
    iot_sitewise = {
      asset_model_id = aws_iotsitewise_asset_model.sustainable_manufacturing.id
      asset_count    = length(aws_iotsitewise_asset.manufacturing_equipment)
    }
    lambda = {
      function_name = aws_lambda_function.carbon_calculator.function_name
      runtime       = aws_lambda_function.carbon_calculator.runtime
    }
    monitoring = {
      dashboard_name = aws_cloudwatch_dashboard.sustainability_dashboard.dashboard_name
      alarm_count    = 2
    }
    automation = {
      eventbridge_rule = aws_cloudwatch_event_rule.daily_sustainability_report.name
      schedule         = var.reporting_schedule
    }
  }
}