# Input variables for the FleetWise Telemetry Analytics infrastructure

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1",   # US East (N. Virginia)
      "eu-central-1" # Europe (Frankfurt)
    ], var.aws_region)
    error_message = "AWS IoT FleetWise is only available in us-east-1 and eu-central-1 regions."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "fleetwise-telemetry"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "fleet_name" {
  description = "Name of the vehicle fleet"
  type        = string
  default     = "production-fleet"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.fleet_name))
    error_message = "Fleet name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "signal_catalog_name" {
  description = "Name of the signal catalog"
  type        = string
  default     = "VehicleSignalCatalog"
}

variable "model_manifest_name" {
  description = "Name of the model manifest"
  type        = string
  default     = "StandardVehicleModel"
}

variable "decoder_manifest_name" {
  description = "Name of the decoder manifest"
  type        = string
  default     = "StandardDecoder"
}

variable "timestream_memory_retention_hours" {
  description = "Memory store retention period in hours for Timestream"
  type        = number
  default     = 24
  
  validation {
    condition     = var.timestream_memory_retention_hours >= 1 && var.timestream_memory_retention_hours <= 8766
    error_message = "Memory retention must be between 1 and 8766 hours."
  }
}

variable "timestream_magnetic_retention_days" {
  description = "Magnetic store retention period in days for Timestream"
  type        = number
  default     = 30
  
  validation {
    condition     = var.timestream_magnetic_retention_days >= 1 && var.timestream_magnetic_retention_days <= 73000
    error_message = "Magnetic retention must be between 1 and 73000 days."
  }
}

variable "data_collection_frequency_ms" {
  description = "Data collection frequency in milliseconds"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.data_collection_frequency_ms >= 1000 && var.data_collection_frequency_ms <= 3600000
    error_message = "Collection frequency must be between 1 second (1000ms) and 1 hour (3600000ms)."
  }
}

variable "vehicle_count" {
  description = "Number of vehicles to create in the fleet"
  type        = number
  default     = 1
  
  validation {
    condition     = var.vehicle_count >= 1 && var.vehicle_count <= 100
    error_message = "Vehicle count must be between 1 and 100."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for data archival"
  type        = bool
  default     = true
}

variable "grafana_workspace_name" {
  description = "Name for the Amazon Managed Grafana workspace"
  type        = string
  default     = "FleetTelemetry"
}

variable "grafana_account_access_type" {
  description = "Account access type for Grafana workspace"
  type        = string
  default     = "CURRENT_ACCOUNT"
  
  validation {
    condition = contains([
      "CURRENT_ACCOUNT",
      "ORGANIZATION"
    ], var.grafana_account_access_type)
    error_message = "Account access type must be either CURRENT_ACCOUNT or ORGANIZATION."
  }
}

variable "grafana_authentication_providers" {
  description = "Authentication providers for Grafana workspace"
  type        = list(string)
  default     = ["AWS_SSO"]
  
  validation {
    condition = alltrue([
      for provider in var.grafana_authentication_providers :
      contains(["AWS_SSO", "SAML"], provider)
    ])
    error_message = "Authentication providers must be from: AWS_SSO, SAML."
  }
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects (use with caution in production)"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}