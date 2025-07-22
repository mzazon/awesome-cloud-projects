# Variables for database performance tuning recipe

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]+[a-z0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "perf-tuning"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-22 characters, start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for RDS Multi-AZ."
  }
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class for the database"
  type        = string
  default     = "db.t3.medium"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
  
  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+$", var.db_engine_version))
    error_message = "DB engine version must be in format X.Y (e.g., 15.4)."
  }
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for the database (GB)"
  type        = number
  default     = 100
  
  validation {
    condition = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling (GB)"
  type        = number
  default     = 200
  
  validation {
    condition = var.db_max_allocated_storage >= var.db_allocated_storage
    error_message = "Max allocated storage must be greater than or equal to allocated storage."
  }
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "db_backup_window" {
  description = "Backup window for the database"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.db_backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "db_maintenance_window" {
  description = "Maintenance window for the database"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.db_maintenance_window))
    error_message = "Maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

# Parameter Group Configuration
variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "postgres15"
  
  validation {
    condition = can(regex("^postgres[0-9]+$", var.parameter_group_family))
    error_message = "Parameter group family must be in format postgresXX."
  }
}

# Performance Tuning Parameters
variable "shared_buffers_mb" {
  description = "Shared buffers setting in MB (should be ~25% of instance memory)"
  type        = number
  default     = 1024
  
  validation {
    condition = var.shared_buffers_mb >= 128 && var.shared_buffers_mb <= 8192
    error_message = "Shared buffers must be between 128 MB and 8192 MB."
  }
}

variable "work_mem_mb" {
  description = "Work memory setting in MB"
  type        = number
  default     = 16
  
  validation {
    condition = var.work_mem_mb >= 4 && var.work_mem_mb <= 256
    error_message = "Work memory must be between 4 MB and 256 MB."
  }
}

variable "maintenance_work_mem_mb" {
  description = "Maintenance work memory setting in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.maintenance_work_mem_mb >= 64 && var.maintenance_work_mem_mb <= 2048
    error_message = "Maintenance work memory must be between 64 MB and 2048 MB."
  }
}

variable "effective_cache_size_gb" {
  description = "Effective cache size setting in GB"
  type        = number
  default     = 3
  
  validation {
    condition = var.effective_cache_size_gb >= 1 && var.effective_cache_size_gb <= 32
    error_message = "Effective cache size must be between 1 GB and 32 GB."
  }
}

variable "max_connections" {
  description = "Maximum number of connections"
  type        = number
  default     = 200
  
  validation {
    condition = var.max_connections >= 50 && var.max_connections <= 5000
    error_message = "Max connections must be between 50 and 5000."
  }
}

variable "random_page_cost" {
  description = "Random page cost for query planner"
  type        = number
  default     = 1.1
  
  validation {
    condition = var.random_page_cost >= 0.1 && var.random_page_cost <= 10.0
    error_message = "Random page cost must be between 0.1 and 10.0."
  }
}

variable "effective_io_concurrency" {
  description = "Effective I/O concurrency"
  type        = number
  default     = 200
  
  validation {
    condition = var.effective_io_concurrency >= 1 && var.effective_io_concurrency <= 1000
    error_message = "Effective I/O concurrency must be between 1 and 1000."
  }
}

# Monitoring Configuration
variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 31, 93, 186, 372, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be one of: 7, 31, 93, 186, 372, 731 days."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60 seconds."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

# Security Configuration
variable "enable_storage_encryption" {
  description = "Enable storage encryption for the database"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the database"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to the database"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Read Replica Configuration
variable "create_read_replica" {
  description = "Whether to create a read replica"
  type        = bool
  default     = true
}

variable "read_replica_instance_class" {
  description = "Instance class for the read replica"
  type        = string
  default     = "db.t3.medium"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.read_replica_instance_class))
    error_message = "Read replica instance class must be a valid RDS instance type."
  }
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}