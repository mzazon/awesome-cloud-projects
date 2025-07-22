# IoT SiteWise Outputs
output "asset_model_id" {
  description = "ID of the created IoT SiteWise asset model"
  value       = aws_iotsitewise_asset_model.production_line_equipment.id
}

output "asset_model_arn" {
  description = "ARN of the created IoT SiteWise asset model"
  value       = aws_iotsitewise_asset_model.production_line_equipment.arn
}

output "asset_id" {
  description = "ID of the created IoT SiteWise asset"
  value       = aws_iotsitewise_asset.production_line_pump.id
}

output "asset_arn" {
  description = "ARN of the created IoT SiteWise asset"
  value       = aws_iotsitewise_asset.production_line_pump.arn
}

output "gateway_id" {
  description = "ID of the created IoT SiteWise gateway"
  value       = aws_iotsitewise_gateway.manufacturing_gateway.id
}

output "gateway_arn" {
  description = "ARN of the created IoT SiteWise gateway"
  value       = aws_iotsitewise_gateway.manufacturing_gateway.arn
}

# Timestream Outputs
output "timestream_database_name" {
  description = "Name of the created Timestream database"
  value       = aws_timestreamwrite_database.industrial_data.database_name
}

output "timestream_database_arn" {
  description = "ARN of the created Timestream database"
  value       = aws_timestreamwrite_database.industrial_data.arn
}

output "timestream_table_name" {
  description = "Name of the created Timestream table"
  value       = aws_timestreamwrite_table.equipment_metrics.table_name
}

output "timestream_table_arn" {
  description = "ARN of the created Timestream table"
  value       = aws_timestreamwrite_table.equipment_metrics.arn
}

# CloudWatch Outputs
output "temperature_alarm_name" {
  description = "Name of the temperature CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_temperature.alarm_name
}

output "temperature_alarm_arn" {
  description = "ARN of the temperature CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_temperature.arn
}

# SNS Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for equipment alerts"
  value       = var.create_sns_topic ? aws_sns_topic.equipment_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for equipment alerts"
  value       = var.create_sns_topic ? aws_sns_topic.equipment_alerts[0].name : null
}

# Property IDs for data ingestion
output "temperature_property_id" {
  description = "Property ID for temperature measurements"
  value       = data.aws_iotsitewise_asset.production_line_pump_data.asset_properties[0].id
}

output "pressure_property_id" {
  description = "Property ID for pressure measurements"
  value       = data.aws_iotsitewise_asset.production_line_pump_data.asset_properties[1].id
}

output "efficiency_property_id" {
  description = "Property ID for operational efficiency calculations"
  value       = data.aws_iotsitewise_asset.production_line_pump_data.asset_properties[2].id
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    project_name           = var.project_name
    environment           = var.environment
    aws_region           = var.aws_region
    asset_model_name     = var.asset_model_name
    asset_name           = var.asset_name
    timestream_database  = "${var.timestream_database_name}-${random_string.suffix.result}"
    timestream_table     = var.timestream_table_name
    gateway_name         = "${var.gateway_name}-${random_string.suffix.result}"
    next_steps = [
      "Configure your industrial equipment to connect to the IoT SiteWise gateway",
      "Set up data ingestion from your OPC-UA or Modbus devices",
      "Configure QuickSight dashboards for real-time monitoring",
      "Set up additional CloudWatch alarms for equipment monitoring",
      "Consider implementing predictive maintenance using Amazon SageMaker"
    ]
  }
}

# Resource URLs for easy access
output "resource_urls" {
  description = "URLs for accessing resources in AWS console"
  value = {
    sitewise_console = "https://console.aws.amazon.com/iotsitewise/home?region=${var.aws_region}#/assets"
    timestream_console = "https://console.aws.amazon.com/timestream/home?region=${var.aws_region}#/databases"
    cloudwatch_console = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#alarmsV2:alarm/list"
    sns_console = "https://console.aws.amazon.com/sns/v3/home?region=${var.aws_region}#/topics"
  }
}