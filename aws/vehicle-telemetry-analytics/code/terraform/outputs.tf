# Output values for the FleetWise Telemetry Analytics infrastructure

# =========================================================================
# General Information
# =========================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "unique_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.suffix
}

# =========================================================================
# S3 Bucket Information
# =========================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data archival"
  value       = aws_s3_bucket.fleetwise_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data archival"
  value       = aws_s3_bucket.fleetwise_data.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.fleetwise_data.region
}

# =========================================================================
# Amazon Timestream Information
# =========================================================================

output "timestream_database_name" {
  description = "Name of the Timestream database"
  value       = aws_timestreamwrite_database.telemetry.database_name
}

output "timestream_database_arn" {
  description = "ARN of the Timestream database"
  value       = aws_timestreamwrite_database.telemetry.arn
}

output "timestream_table_name" {
  description = "Name of the Timestream table"
  value       = aws_timestreamwrite_table.vehicle_metrics.table_name
}

output "timestream_table_arn" {
  description = "ARN of the Timestream table"
  value       = aws_timestreamwrite_table.vehicle_metrics.arn
}

output "timestream_retention_config" {
  description = "Timestream table retention configuration"
  value = {
    memory_store_hours   = var.timestream_memory_retention_hours
    magnetic_store_days = var.timestream_magnetic_retention_days
  }
}

# =========================================================================
# IAM Role Information
# =========================================================================

output "fleetwise_service_role_name" {
  description = "Name of the FleetWise service role"
  value       = aws_iam_role.fleetwise_service.name
}

output "fleetwise_service_role_arn" {
  description = "ARN of the FleetWise service role"
  value       = aws_iam_role.fleetwise_service.arn
}

# =========================================================================
# AWS IoT FleetWise Resources
# =========================================================================

output "signal_catalog_name" {
  description = "Name of the signal catalog"
  value       = aws_iotfleetwise_signal_catalog.vehicle_signals.name
}

output "signal_catalog_arn" {
  description = "ARN of the signal catalog"
  value       = aws_iotfleetwise_signal_catalog.vehicle_signals.arn
}

output "model_manifest_name" {
  description = "Name of the model manifest"
  value       = aws_iotfleetwise_model_manifest.vehicle_model.name
}

output "model_manifest_arn" {
  description = "ARN of the model manifest"
  value       = aws_iotfleetwise_model_manifest.vehicle_model.arn
}

output "decoder_manifest_name" {
  description = "Name of the decoder manifest"
  value       = aws_iotfleetwise_decoder_manifest.vehicle_decoder.name
}

output "decoder_manifest_arn" {
  description = "ARN of the decoder manifest"
  value       = aws_iotfleetwise_decoder_manifest.vehicle_decoder.arn
}

output "fleet_id" {
  description = "ID of the vehicle fleet"
  value       = aws_iotfleetwise_fleet.vehicle_fleet.fleet_id
}

output "fleet_arn" {
  description = "ARN of the vehicle fleet"
  value       = aws_iotfleetwise_fleet.vehicle_fleet.arn
}

output "campaign_name" {
  description = "Name of the data collection campaign"
  value       = aws_iotfleetwise_campaign.telemetry_campaign.name
}

output "campaign_arn" {
  description = "ARN of the data collection campaign"
  value       = aws_iotfleetwise_campaign.telemetry_campaign.arn
}

output "campaign_status" {
  description = "Status of the data collection campaign"
  value       = aws_iotfleetwise_campaign.telemetry_campaign.status
}

# =========================================================================
# Vehicle Information
# =========================================================================

output "vehicle_count" {
  description = "Number of vehicles created"
  value       = var.vehicle_count
}

output "iot_thing_names" {
  description = "Names of the IoT things representing vehicles"
  value       = aws_iot_thing.vehicles[*].name
}

output "iot_thing_arns" {
  description = "ARNs of the IoT things representing vehicles"
  value       = aws_iot_thing.vehicles[*].arn
}

output "fleetwise_vehicle_names" {
  description = "Names of the FleetWise vehicles"
  value       = aws_iotfleetwise_vehicle.fleet_vehicles[*].vehicle_name
}

# =========================================================================
# Amazon Managed Grafana Information
# =========================================================================

output "grafana_workspace_id" {
  description = "ID of the Grafana workspace"
  value       = aws_grafana_workspace.fleet_telemetry.id
}

output "grafana_workspace_arn" {
  description = "ARN of the Grafana workspace"
  value       = aws_grafana_workspace.fleet_telemetry.arn
}

output "grafana_workspace_endpoint" {
  description = "Endpoint URL of the Grafana workspace"
  value       = aws_grafana_workspace.fleet_telemetry.endpoint
}

output "grafana_workspace_url" {
  description = "Complete URL to access the Grafana workspace"
  value       = "https://${aws_grafana_workspace.fleet_telemetry.endpoint}"
}

output "grafana_service_account_id" {
  description = "ID of the Grafana service account"
  value       = aws_grafana_workspace_service_account.terraform_sa.service_account_id
}

# =========================================================================
# Configuration Information
# =========================================================================

output "data_collection_frequency_ms" {
  description = "Data collection frequency in milliseconds"
  value       = var.data_collection_frequency_ms
}

output "data_collection_frequency_seconds" {
  description = "Data collection frequency in seconds"
  value       = var.data_collection_frequency_ms / 1000
}

output "collected_signals" {
  description = "List of vehicle signals being collected"
  value = [
    "Vehicle.Engine.RPM",
    "Vehicle.Speed",
    "Vehicle.Engine.Temperature",
    "Vehicle.FuelLevel"
  ]
}

# =========================================================================
# Next Steps and Commands
# =========================================================================

output "timestream_query_example" {
  description = "Example Timestream query to view collected data"
  value = "SELECT * FROM ${local.timestream_db_name}.${local.timestream_table_name} ORDER BY time DESC LIMIT 10"
}

output "grafana_configuration_steps" {
  description = "Steps to configure Timestream data source in Grafana"
  value = [
    "1. Navigate to the Grafana workspace URL above",
    "2. Go to Configuration > Data Sources",
    "3. Add Amazon Timestream data source",
    "4. Configure with Database: ${local.timestream_db_name}",
    "5. Configure with Table: ${local.timestream_table_name}",
    "6. Use AWS credentials for authentication"
  ]
}

output "aws_cli_validation_commands" {
  description = "AWS CLI commands to validate the deployment"
  value = {
    check_campaign_status = "aws iotfleetwise get-campaign --name ${aws_iotfleetwise_campaign.telemetry_campaign.name}"
    query_timestream_data = "aws timestream-query query --query-string \"SELECT * FROM ${local.timestream_db_name}.${local.timestream_table_name} ORDER BY time DESC LIMIT 5\""
    list_fleet_vehicles   = "aws iotfleetwise list-vehicles-in-fleet --fleet-id ${local.fleet_name}"
  }
}

# =========================================================================
# Important Notes
# =========================================================================

output "important_notes" {
  description = "Important information about the deployment"
  value = {
    fleetwise_regions = "AWS IoT FleetWise is only available in us-east-1 and eu-central-1 regions"
    edge_agent_requirement = "Vehicles require AWS IoT FleetWise Edge Agent installation to send telemetry data"
    grafana_access = "Configure AWS SSO or SAML authentication to access Grafana workspace"
    cost_optimization = "Monitor Timestream usage and adjust retention policies to optimize costs"
    security_note = "Ensure proper IAM permissions and IoT device certificates for production deployments"
  }
}

output "cost_estimation" {
  description = "Estimated monthly costs for this deployment"
  value = {
    timestream_note = "Timestream costs depend on data ingestion volume and query frequency"
    grafana_note = "Managed Grafana workspace costs approximately $9 per active user per month"
    s3_note = "S3 costs depend on data volume and storage class"
    monitoring_recommendation = "Use AWS Cost Explorer to monitor actual costs"
  }
}