# Input Variables for Supply Chain Transparency Infrastructure
# This file defines all configurable parameters for the supply chain transparency system

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "supply-chain"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud SQL Configuration
variable "db_instance_tier" {
  description = "Cloud SQL instance tier (machine type)"
  type        = string
  default     = "db-custom-2-8192"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2",
      "db-n1-standard-4", "db-n1-standard-8", "db-custom-2-8192", "db-custom-4-16384"
    ], var.db_instance_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_version" {
  description = "PostgreSQL version for Cloud SQL instance"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16"
    ], var.db_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "db_backup_enabled" {
  description = "Enable automated backups for Cloud SQL instance"
  type        = bool
  default     = true
}

variable "db_high_availability" {
  description = "Enable high availability for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = true
}

# Blockchain Node Engine Configuration
variable "blockchain_network" {
  description = "Blockchain network (MAINNET, GOERLI, SEPOLIA)"
  type        = string
  default     = "MAINNET"
  validation {
    condition = contains([
      "MAINNET", "GOERLI", "SEPOLIA"
    ], var.blockchain_network)
    error_message = "Blockchain network must be MAINNET, GOERLI, or SEPOLIA."
  }
}

variable "blockchain_node_type" {
  description = "Blockchain node type (FULL, ARCHIVE)"
  type        = string
  default     = "FULL"
  validation {
    condition = contains([
      "FULL", "ARCHIVE"
    ], var.blockchain_node_type)
    error_message = "Blockchain node type must be FULL or ARCHIVE."
  }
}

variable "blockchain_execution_client" {
  description = "Blockchain execution client (GETH, ERIGON)"
  type        = string
  default     = "GETH"
  validation {
    condition = contains([
      "GETH", "ERIGON"
    ], var.blockchain_execution_client)
    error_message = "Execution client must be GETH or ERIGON."
  }
}

variable "blockchain_consensus_client" {
  description = "Blockchain consensus client"
  type        = string
  default     = "LIGHTHOUSE"
  validation {
    condition = contains([
      "LIGHTHOUSE"
    ], var.blockchain_consensus_client)
    error_message = "Consensus client must be LIGHTHOUSE."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout > 0 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances > 0 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '604800s')."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud KMS Configuration
variable "kms_key_rotation_period" {
  description = "Key rotation period for Cloud KMS keys"
  type        = string
  default     = "7776000s" # 90 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.kms_key_rotation_period))
    error_message = "Key rotation period must be in seconds format (e.g., '7776000s')."
  }
}

variable "kms_key_destroy_scheduled_duration" {
  description = "Scheduled destruction duration for Cloud KMS keys"
  type        = string
  default     = "86400s" # 24 hours
  validation {
    condition     = can(regex("^[0-9]+s$", var.kms_key_destroy_scheduled_duration))
    error_message = "Destroy scheduled duration must be in seconds format (e.g., '86400s')."
  }
}

# Networking Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for the VPC network"
  type        = bool
  default     = true
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "VPC CIDR block must be a valid CIDR notation."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR block must be a valid CIDR notation."
  }
}

# Security Configuration
variable "enable_ssl_enforcement" {
  description = "Enable SSL enforcement for Cloud SQL connections"
  type        = bool
  default     = true
}

variable "allowed_source_ranges" {
  description = "List of CIDR blocks allowed to access resources"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_source_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All source ranges must be valid CIDR blocks."
  }
}

# Monitoring and Logging Configuration
variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring for all resources"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days > 0 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 days."
  }
}

# Resource Labeling
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    project    = "supply-chain-transparency"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}