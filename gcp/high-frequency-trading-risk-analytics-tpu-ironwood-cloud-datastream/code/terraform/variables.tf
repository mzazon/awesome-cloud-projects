# Variables for high-frequency trading risk analytics infrastructure

variable "project_id" {
  description = "Google Cloud Project ID for the high-frequency trading analytics infrastructure"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-southeast1", "asia-east1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports TPU resources."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources like TPU"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must be provided."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "staging", "prod", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "trading_dataset_id" {
  description = "BigQuery dataset ID for trading analytics data"
  type        = string
  default     = "trading_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.trading_dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "tpu_accelerator_type" {
  description = "TPU accelerator type for Ironwood cluster"
  type        = string
  default     = "v6e-256"
  validation {
    condition = contains([
      "v6e-1", "v6e-4", "v6e-8", "v6e-16", "v6e-32", "v6e-64", "v6e-128", "v6e-256"
    ], var.tpu_accelerator_type)
    error_message = "TPU accelerator type must be a valid v6e Ironwood type."
  }
}

variable "tpu_runtime_version" {
  description = "TPU runtime version for machine learning workloads"
  type        = string
  default     = "tpu-vm-tf-2.17.0"
  validation {
    condition     = can(regex("^tpu-vm-tf-[0-9]\\.[0-9]+\\.[0-9]+$", var.tpu_runtime_version))
    error_message = "TPU runtime version must be in format tpu-vm-tf-X.Y.Z."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run risk analytics API service"
  type        = string
  default     = "4Gi"
  validation {
    condition = contains([
      "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.cloud_run_memory)
    error_message = "Cloud Run memory must be a valid memory size (1Gi, 2Gi, 4Gi, 8Gi, 16Gi, 32Gi)."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run risk analytics API service"
  type        = string
  default     = "4"
  validation {
    condition = contains([
      "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "Cloud Run CPU must be a valid CPU count (1, 2, 4, 6, 8)."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum concurrent requests per Cloud Run instance"
  type        = number
  default     = 1000
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Cloud Run concurrency must be between 1 and 1000."
  }
}

variable "enable_datastream" {
  description = "Enable Cloud Datastream for real-time database replication"
  type        = bool
  default     = true
}

variable "source_database_type" {
  description = "Type of source database for Datastream (mysql, postgresql, oracle, sqlserver)"
  type        = string
  default     = "mysql"
  validation {
    condition = contains([
      "mysql", "postgresql", "oracle", "sqlserver"
    ], var.source_database_type)
    error_message = "Source database type must be one of: mysql, postgresql, oracle, sqlserver."
  }
}

variable "source_database_host" {
  description = "Hostname or IP address of the source trading database"
  type        = string
  default     = ""
}

variable "source_database_port" {
  description = "Port number of the source trading database"
  type        = number
  default     = 3306
  validation {
    condition     = var.source_database_port >= 1 && var.source_database_port <= 65535
    error_message = "Database port must be between 1 and 65535."
  }
}

variable "source_database_username" {
  description = "Username for connecting to the source trading database"
  type        = string
  default     = "datastream_user"
  sensitive   = true
}

variable "source_database_password" {
  description = "Password for connecting to the source trading database"
  type        = string
  default     = ""
  sensitive   = true
  validation {
    condition     = length(var.source_database_password) >= 8 || var.source_database_password == ""
    error_message = "Database password must be at least 8 characters long when provided."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting for the trading system"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable customer-managed encryption keys for sensitive data"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "hft-risk-analytics"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels are allowed per resource."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "network_name" {
  description = "Name of the VPC network for the infrastructure"
  type        = string
  default     = "hft-risk-network"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.network_name))
    error_message = "Network name must be 1-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "tpu_cidr_block" {
  description = "CIDR block for TPU nodes (must be /29)"
  type        = string
  default     = "10.0.1.0/29"
  validation {
    condition     = can(regex("/29$", var.tpu_cidr_block))
    error_message = "TPU CIDR block must be a /29 subnet."
  }
}

variable "bigquery_data_freshness" {
  description = "Data freshness for BigQuery streaming inserts (in seconds)"
  type        = string
  default     = "300s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.bigquery_data_freshness))
    error_message = "Data freshness must be specified in seconds format (e.g., 300s)."
  }
}