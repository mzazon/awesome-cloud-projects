# Main Terraform configuration for FleetWise Telemetry Analytics

# Data sources
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate unique identifiers for resources
  suffix                 = random_string.suffix.result
  fleet_name            = "${var.fleet_name}-${local.suffix}"
  timestream_db_name    = "${var.project_name}_db_${local.suffix}"
  timestream_table_name = "vehicle_metrics"
  s3_bucket_name        = "${var.project_name}-data-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    ProjectName = var.project_name
    FleetName   = local.fleet_name
  })
}

# =========================================================================
# S3 Bucket for Data Archival
# =========================================================================

resource "aws_s3_bucket" "fleetwise_data" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = "FleetWise Data Archive"
    Description = "S3 bucket for archiving vehicle telemetry data"
  })
}

resource "aws_s3_bucket_versioning" "fleetwise_data" {
  bucket = aws_s3_bucket.fleetwise_data.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fleetwise_data" {
  bucket = aws_s3_bucket.fleetwise_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "fleetwise_data" {
  bucket = aws_s3_bucket.fleetwise_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =========================================================================
# Amazon Timestream Database and Table
# =========================================================================

resource "aws_timestreamwrite_database" "telemetry" {
  database_name = local.timestream_db_name

  tags = merge(local.common_tags, {
    Name        = "Vehicle Telemetry Database"
    Description = "Timestream database for vehicle telemetry data"
  })
}

resource "aws_timestreamwrite_table" "vehicle_metrics" {
  database_name = aws_timestreamwrite_database.telemetry.database_name
  table_name    = local.timestream_table_name

  retention_properties {
    memory_store_retention_period_in_hours   = var.timestream_memory_retention_hours
    magnetic_store_retention_period_in_days  = var.timestream_magnetic_retention_days
  }

  tags = merge(local.common_tags, {
    Name        = "Vehicle Metrics Table"
    Description = "Timestream table for storing vehicle telemetry metrics"
  })
}

# =========================================================================
# IAM Role and Policies for FleetWise
# =========================================================================

# Trust policy document for FleetWise service
data "aws_iam_policy_document" "fleetwise_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["iotfleetwise.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for FleetWise service
resource "aws_iam_role" "fleetwise_service" {
  name               = "FleetWiseServiceRole-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.fleetwise_trust.json

  tags = merge(local.common_tags, {
    Name        = "FleetWise Service Role"
    Description = "IAM role for AWS IoT FleetWise service operations"
  })
}

# Policy document for Timestream write access
data "aws_iam_policy_document" "timestream_write" {
  statement {
    effect = "Allow"
    
    actions = [
      "timestream:WriteRecords",
      "timestream:DescribeEndpoints"
    ]
    
    resources = [
      aws_timestreamwrite_table.vehicle_metrics.arn
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "timestream:DescribeEndpoints"
    ]
    
    resources = ["*"]
  }
}

# Attach Timestream policy to FleetWise role
resource "aws_iam_role_policy" "timestream_write" {
  name   = "TimestreamWritePolicy"
  role   = aws_iam_role.fleetwise_service.id
  policy = data.aws_iam_policy_document.timestream_write.json
}

# =========================================================================
# AWS IoT FleetWise Signal Catalog
# =========================================================================

resource "aws_iotfleetwise_signal_catalog" "vehicle_signals" {
  name        = var.signal_catalog_name
  description = "Standard vehicle telemetry signals"

  # Vehicle branch structure
  node {
    branch {
      fully_qualified_name = "Vehicle"
      description         = "Root vehicle branch"
    }
  }

  node {
    branch {
      fully_qualified_name = "Vehicle.Engine"
      description         = "Engine-related signals"
    }
  }

  # Engine RPM sensor
  node {
    sensor {
      fully_qualified_name = "Vehicle.Engine.RPM"
      data_type           = "DOUBLE"
      description         = "Engine revolutions per minute"
      unit               = "rpm"
      min                = 0
      max                = 8000
    }
  }

  # Vehicle speed sensor
  node {
    sensor {
      fully_qualified_name = "Vehicle.Speed"
      data_type           = "DOUBLE"
      description         = "Vehicle speed"
      unit               = "km/h"
      min                = 0
      max                = 300
    }
  }

  # Engine temperature sensor
  node {
    sensor {
      fully_qualified_name = "Vehicle.Engine.Temperature"
      data_type           = "DOUBLE"
      description         = "Engine coolant temperature"
      unit               = "Celsius"
      min                = -40
      max                = 200
    }
  }

  # Fuel level sensor
  node {
    sensor {
      fully_qualified_name = "Vehicle.FuelLevel"
      data_type           = "DOUBLE"
      description         = "Fuel tank level percentage"
      unit               = "Percentage"
      min                = 0
      max                = 100
    }
  }

  tags = merge(local.common_tags, {
    Name        = "Vehicle Signal Catalog"
    Description = "Signal catalog defining standard vehicle telemetry"
  })
}

# =========================================================================
# AWS IoT FleetWise Model Manifest
# =========================================================================

resource "aws_iotfleetwise_model_manifest" "vehicle_model" {
  name               = var.model_manifest_name
  description        = "Model for standard fleet vehicles"
  signal_catalog_arn = aws_iotfleetwise_signal_catalog.vehicle_signals.arn

  nodes = [
    "Vehicle.Engine.RPM",
    "Vehicle.Speed",
    "Vehicle.Engine.Temperature",
    "Vehicle.FuelLevel"
  ]

  status = "ACTIVE"

  tags = merge(local.common_tags, {
    Name        = "Vehicle Model Manifest"
    Description = "Model manifest defining signals for fleet vehicles"
  })
}

# =========================================================================
# AWS IoT FleetWise Decoder Manifest
# =========================================================================

resource "aws_iotfleetwise_decoder_manifest" "vehicle_decoder" {
  name               = var.decoder_manifest_name
  description        = "Decoder for standard vehicle signals"
  model_manifest_arn = aws_iotfleetwise_model_manifest.vehicle_model.arn

  # Engine RPM decoder
  signal_decoders {
    fully_qualified_name = "Vehicle.Engine.RPM"
    type                = "CAN_SIGNAL"

    can_signal {
      message_id    = 419364097
      is_big_endian = false
      is_signed     = false
      start_bit     = 24
      offset        = 0.0
      factor        = 0.25
      length        = 16
    }
  }

  # Vehicle speed decoder
  signal_decoders {
    fully_qualified_name = "Vehicle.Speed"
    type                = "CAN_SIGNAL"

    can_signal {
      message_id    = 419364352
      is_big_endian = false
      is_signed     = false
      start_bit     = 0
      offset        = 0.0
      factor        = 0.01
      length        = 16
    }
  }

  status = "ACTIVE"

  tags = merge(local.common_tags, {
    Name        = "Vehicle Decoder Manifest"
    Description = "Decoder manifest for translating CAN signals"
  })
}

# =========================================================================
# AWS IoT FleetWise Fleet
# =========================================================================

resource "aws_iotfleetwise_fleet" "vehicle_fleet" {
  fleet_id           = local.fleet_name
  description        = "Production vehicle fleet for telemetry collection"
  signal_catalog_arn = aws_iotfleetwise_signal_catalog.vehicle_signals.arn

  tags = merge(local.common_tags, {
    Name        = "Vehicle Fleet"
    Description = "Fleet containing vehicles for telemetry collection"
  })
}

# =========================================================================
# AWS IoT Things and FleetWise Vehicles
# =========================================================================

# Create IoT things for vehicles
resource "aws_iot_thing" "vehicles" {
  count = var.vehicle_count
  name  = "vehicle-${format("%03d", count.index + 1)}-${local.suffix}"

  tags = merge(local.common_tags, {
    Name        = "Vehicle IoT Thing ${count.index + 1}"
    Description = "IoT thing representing vehicle ${count.index + 1}"
    VehicleId   = count.index + 1
  })
}

# Create FleetWise vehicles
resource "aws_iotfleetwise_vehicle" "fleet_vehicles" {
  count                = var.vehicle_count
  vehicle_name         = aws_iot_thing.vehicles[count.index].name
  model_manifest_arn   = aws_iotfleetwise_model_manifest.vehicle_model.arn
  decoder_manifest_arn = aws_iotfleetwise_decoder_manifest.vehicle_decoder.arn

  tags = merge(local.common_tags, {
    Name        = "FleetWise Vehicle ${count.index + 1}"
    Description = "FleetWise vehicle configuration for ${aws_iot_thing.vehicles[count.index].name}"
    VehicleId   = count.index + 1
  })
}

# Associate vehicles with fleet
resource "aws_iotfleetwise_vehicle_fleet_association" "fleet_associations" {
  count        = var.vehicle_count
  vehicle_name = aws_iotfleetwise_vehicle.fleet_vehicles[count.index].vehicle_name
  fleet_id     = aws_iotfleetwise_fleet.vehicle_fleet.fleet_id
}

# =========================================================================
# AWS IoT FleetWise Data Collection Campaign
# =========================================================================

resource "aws_iotfleetwise_campaign" "telemetry_campaign" {
  name                = "TelemetryCampaign-${local.suffix}"
  description         = "Collect vehicle telemetry data for fleet analytics"
  signal_catalog_arn  = aws_iotfleetwise_signal_catalog.vehicle_signals.arn
  target_arn          = aws_iotfleetwise_fleet.vehicle_fleet.arn

  # Configure Timestream as data destination
  data_destination_configs {
    timestream_config {
      timestream_table_arn = aws_timestreamwrite_table.vehicle_metrics.arn
      execution_role_arn   = aws_iam_role.fleetwise_service.arn
    }
  }

  # Time-based collection scheme
  collection_scheme {
    time_based_collection_scheme {
      period_ms = var.data_collection_frequency_ms
    }
  }

  # Define signals to collect
  signals_to_collect {
    name = "Vehicle.Engine.RPM"
  }

  signals_to_collect {
    name = "Vehicle.Speed"
  }

  signals_to_collect {
    name = "Vehicle.Engine.Temperature"
  }

  signals_to_collect {
    name = "Vehicle.FuelLevel"
  }

  # Campaign configuration
  post_trigger_collection_duration = 0
  diagnostics_mode                 = "OFF"
  spooling_mode                   = "TO_DISK"
  compression                     = "SNAPPY"

  # Auto-start the campaign
  action = "RESUME"

  tags = merge(local.common_tags, {
    Name        = "Telemetry Collection Campaign"
    Description = "Campaign for collecting vehicle telemetry data"
  })

  depends_on = [
    aws_iotfleetwise_vehicle_fleet_association.fleet_associations,
    aws_iam_role_policy.timestream_write
  ]
}

# =========================================================================
# Amazon Managed Grafana Workspace
# =========================================================================

resource "aws_grafana_workspace" "fleet_telemetry" {
  name                     = "${var.grafana_workspace_name}-${local.suffix}"
  description              = "Vehicle telemetry dashboards and monitoring"
  account_access_type      = var.grafana_account_access_type
  authentication_providers = var.grafana_authentication_providers
  permission_type          = "SERVICE_MANAGED"
  
  # Enable Timestream as a data source
  data_sources = ["TIMESTREAM"]

  # Notification destinations (optional)
  notification_destinations = ["SNS"]

  tags = merge(local.common_tags, {
    Name        = "Fleet Telemetry Grafana Workspace"
    Description = "Managed Grafana workspace for vehicle telemetry visualization"
  })
}

# Service account for Grafana API access
resource "aws_grafana_workspace_service_account" "terraform_sa" {
  name         = "terraform-sa"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.fleet_telemetry.id
}

# API key for service account
resource "aws_grafana_workspace_service_account_token" "terraform_key" {
  name               = "terraform-api-key"
  service_account_id = aws_grafana_workspace_service_account.terraform_sa.service_account_id
  workspace_id       = aws_grafana_workspace.fleet_telemetry.id
  seconds_to_live    = 3600 # 1 hour
}