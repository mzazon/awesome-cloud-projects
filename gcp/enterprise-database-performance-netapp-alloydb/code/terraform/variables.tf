# Variable Definitions for Enterprise Database Performance Solution
# This file defines all configurable parameters for the infrastructure deployment

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The primary Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The primary Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

# Network Configuration
variable "vpc_name" {
  description = "Name of the VPC network for the enterprise database infrastructure"
  type        = string
  default     = "enterprise-db-vpc"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.vpc_name))
    error_message = "VPC name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "subnet_name" {
  description = "Name of the subnet for database resources"
  type        = string
  default     = "enterprise-db-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the database subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_ip_range_cidr" {
  description = "CIDR range for private service networking"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.private_ip_range_cidr, 0))
    error_message = "Private IP range CIDR must be a valid IPv4 CIDR block."
  }
}

# AlloyDB Configuration
variable "alloydb_cluster_id" {
  description = "Unique identifier for the AlloyDB cluster"
  type        = string
  default     = ""
  validation {
    condition = var.alloydb_cluster_id == "" || can(regex("^[a-z0-9-]+$", var.alloydb_cluster_id))
    error_message = "AlloyDB cluster ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "alloydb_database_version" {
  description = "PostgreSQL version for AlloyDB cluster"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15"
    ], var.alloydb_database_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "alloydb_password" {
  description = "Password for the AlloyDB cluster root user"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.alloydb_password) >= 8
    error_message = "AlloyDB password must be at least 8 characters long."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "backup_start_time" {
  description = "Time of day for automated backups (24-hour format, e.g., '02:00')"
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

# Primary Instance Configuration
variable "primary_cpu_count" {
  description = "Number of CPUs for the AlloyDB primary instance"
  type        = number
  default     = 16
  validation {
    condition = contains([2, 4, 8, 16, 32, 64, 96], var.primary_cpu_count)
    error_message = "Primary CPU count must be one of: 2, 4, 8, 16, 32, 64, 96."
  }
}

variable "primary_memory_size_gb" {
  description = "Memory size in GB for the AlloyDB primary instance"
  type        = number
  default     = 64
  validation {
    condition     = var.primary_memory_size_gb >= 4 && var.primary_memory_size_gb <= 768
    error_message = "Primary memory size must be between 4 and 768 GB."
  }
}

# Read Replica Configuration
variable "enable_read_replicas" {
  description = "Whether to create read replicas for analytical workloads"
  type        = bool
  default     = true
}

variable "replica_cpu_count" {
  description = "Number of CPUs for AlloyDB read replica instances"
  type        = number
  default     = 8
  validation {
    condition = contains([2, 4, 8, 16, 32, 64, 96], var.replica_cpu_count)
    error_message = "Replica CPU count must be one of: 2, 4, 8, 16, 32, 64, 96."
  }
}

variable "replica_memory_size_gb" {
  description = "Memory size in GB for AlloyDB read replica instances"
  type        = number
  default     = 32
  validation {
    condition     = var.replica_memory_size_gb >= 4 && var.replica_memory_size_gb <= 768
    error_message = "Replica memory size must be between 4 and 768 GB."
  }
}

variable "read_pool_node_count" {
  description = "Number of nodes in the read pool for replica instances"
  type        = number
  default     = 3
  validation {
    condition     = var.read_pool_node_count >= 1 && var.read_pool_node_count <= 20
    error_message = "Read pool node count must be between 1 and 20."
  }
}

# NetApp Volumes Configuration
variable "netapp_storage_pool_name" {
  description = "Name of the NetApp storage pool"
  type        = string
  default     = ""
  validation {
    condition = var.netapp_storage_pool_name == "" || can(regex("^[a-z0-9-]+$", var.netapp_storage_pool_name))
    error_message = "NetApp storage pool name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "netapp_storage_pool_capacity_tib" {
  description = "Capacity of the NetApp storage pool in TiB"
  type        = number
  default     = 20
  validation {
    condition     = var.netapp_storage_pool_capacity_tib >= 4 && var.netapp_storage_pool_capacity_tib <= 500
    error_message = "NetApp storage pool capacity must be between 4 and 500 TiB."
  }
}

variable "netapp_storage_service_level" {
  description = "Service level for NetApp storage pool"
  type        = string
  default     = "FLEX"
  validation {
    condition = contains([
      "STANDARD", "PREMIUM", "EXTREME", "FLEX"
    ], var.netapp_storage_service_level)
    error_message = "NetApp storage service level must be one of: STANDARD, PREMIUM, EXTREME, FLEX."
  }
}

variable "netapp_volume_name" {
  description = "Name of the NetApp volume for database data"
  type        = string
  default     = ""
  validation {
    condition = var.netapp_volume_name == "" || can(regex("^[a-z0-9-]+$", var.netapp_volume_name))
    error_message = "NetApp volume name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "netapp_volume_capacity_gib" {
  description = "Capacity of the NetApp volume in GiB"
  type        = number
  default     = 10240  # 10 TiB
  validation {
    condition     = var.netapp_volume_capacity_gib >= 1024 && var.netapp_volume_capacity_gib <= 102400
    error_message = "NetApp volume capacity must be between 1024 GiB (1 TiB) and 102400 GiB (100 TiB)."
  }
}

variable "netapp_volume_share_name" {
  description = "NFS share name for the NetApp volume"
  type        = string
  default     = "enterprise-db-data"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.netapp_volume_share_name))
    error_message = "NetApp volume share name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "netapp_protocols" {
  description = "List of protocols supported by the NetApp volume"
  type        = list(string)
  default     = ["NFSV4"]
  validation {
    condition = alltrue([
      for protocol in var.netapp_protocols : contains(["NFSV3", "NFSV4", "SMB"], protocol)
    ])
    error_message = "NetApp protocols must be from: NFSV3, NFSV4, SMB."
  }
}

# Security Configuration
variable "enable_kms_encryption" {
  description = "Whether to enable customer-managed encryption with Cloud KMS"
  type        = bool
  default     = true
}

variable "kms_keyring_name" {
  description = "Name of the KMS keyring for database encryption"
  type        = string
  default     = "alloydb-keyring"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_keyring_name))
    error_message = "KMS keyring name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "kms_key_name" {
  description = "Name of the KMS key for database encryption"
  type        = string
  default     = "alloydb-key"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_key_name))
    error_message = "KMS key name must contain only letters, numbers, underscores, and hyphens."
  }
}

# Load Balancing Configuration
variable "enable_load_balancer" {
  description = "Whether to create internal load balancer for database connections"
  type        = bool
  default     = true
}

variable "load_balancer_ip" {
  description = "Static IP address for the internal load balancer"
  type        = string
  default     = "10.0.0.100"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.load_balancer_ip))
    error_message = "Load balancer IP must be a valid IPv4 address."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Whether to enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_cpu_threshold" {
  description = "CPU utilization threshold for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.alert_cpu_threshold >= 0.0 && var.alert_cpu_threshold <= 1.0
    error_message = "Alert CPU threshold must be between 0.0 and 1.0."
  }
}

variable "alert_memory_threshold" {
  description = "Memory utilization threshold for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.alert_memory_threshold >= 0.0 && var.alert_memory_threshold <= 1.0
    error_message = "Alert memory threshold must be between 0.0 and 1.0."
  }
}

# Resource Labeling
variable "environment" {
  description = "Environment name for resource labeling (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  validation {
    condition = contains([
      "development", "dev", "staging", "stage", "production", "prod", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, dev, staging, stage, production, prod, test."
  }
}

variable "owner" {
  description = "Owner of the resources for labeling and cost tracking"
  type        = string
  default     = "database-team"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.owner))
    error_message = "Owner must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource labeling"
  type        = string
  default     = "enterprise-database"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center for billing and resource allocation"
  type        = string
  default     = "database-infrastructure"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cost_center))
    error_message = "Cost center must contain only lowercase letters, numbers, and hyphens."
  }
}