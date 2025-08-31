# =========================================================================
# Variables for TCP Resource Connectivity with VPC Lattice and CloudWatch
# =========================================================================

# ---------------------------------------------------------------------------
# General Configuration Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "VPCLatticeDemo"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Purpose     = "TCP-Resource-Connectivity"
  }
}

# ---------------------------------------------------------------------------
# VPC Lattice Configuration Variables
# ---------------------------------------------------------------------------

variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = "database-service-network"

  validation {
    condition     = length(var.service_network_name) <= 63 && can(regex("^[a-z0-9-]+$", var.service_network_name))
    error_message = "Service network name must be 63 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_service_name" {
  description = "Name for the VPC Lattice database service"
  type        = string
  default     = "rds-database-service"

  validation {
    condition     = length(var.database_service_name) <= 63 && can(regex("^[a-z0-9-]+$", var.database_service_name))
    error_message = "Database service name must be 63 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "target_group_name" {
  description = "Name for the VPC Lattice target group"
  type        = string
  default     = "rds-tcp-targets"

  validation {
    condition     = length(var.target_group_name) <= 63 && can(regex("^[a-z0-9-]+$", var.target_group_name))
    error_message = "Target group name must be 63 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

# ---------------------------------------------------------------------------
# RDS Database Configuration Variables
# ---------------------------------------------------------------------------

variable "rds_instance_id" {
  description = "Identifier for the RDS database instance"
  type        = string
  default     = "vpc-lattice-db"

  validation {
    condition     = length(var.rds_instance_id) <= 60 && can(regex("^[a-z][a-z0-9-]*$", var.rds_instance_id))
    error_message = "RDS instance identifier must start with a letter, be 60 characters or less, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "db_instance_class" {
  description = "RDS instance class for the MySQL database"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition = contains([
      "db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large",
      "db.t3.xlarge", "db.t3.2xlarge", "db.m5.large", "db.m5.xlarge",
      "db.m5.2xlarge", "db.m5.4xlarge", "db.r5.large", "db.r5.xlarge"
    ], var.db_instance_class)
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "mysql_engine_version" {
  description = "MySQL engine version for RDS instance"
  type        = string
  default     = "8.0.35"

  validation {
    condition     = can(regex("^8\\.0\\.[0-9]+$", var.mysql_engine_version))
    error_message = "MySQL engine version must be a valid 8.0.x version."
  }
}

variable "db_username" {
  description = "Master username for the RDS database"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.db_username) >= 1 && length(var.db_username) <= 16 && can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_username))
    error_message = "Database username must be 1-16 characters, start with a letter, and contain only letters, numbers, and underscores."
  }
}

variable "db_password" {
  description = "Master password for the RDS database"
  type        = string
  default     = "MySecurePassword123!"
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128
    error_message = "Database password must be between 8 and 128 characters."
  }
}

variable "db_allocated_storage" {
  description = "Allocated storage size for RDS instance in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "mysql_port" {
  description = "Port number for MySQL database connections"
  type        = number
  default     = 3306

  validation {
    condition     = var.mysql_port >= 1024 && var.mysql_port <= 65535
    error_message = "MySQL port must be between 1024 and 65535."
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Monitoring Variables
# ---------------------------------------------------------------------------

variable "high_connection_threshold" {
  description = "Threshold for high connection count CloudWatch alarm"
  type        = number
  default     = 50

  validation {
    condition     = var.high_connection_threshold > 0 && var.high_connection_threshold <= 1000
    error_message = "High connection threshold must be between 1 and 1000."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS instance"
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Monitoring interval for RDS enhanced monitoring (in seconds)"
  type        = number
  default     = 60

  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

# ---------------------------------------------------------------------------
# Network Configuration Variables
# ---------------------------------------------------------------------------

variable "use_default_vpc" {
  description = "Whether to use the default VPC for deployment"
  type        = bool
  default     = true
}

variable "custom_vpc_id" {
  description = "Custom VPC ID to use instead of default VPC (when use_default_vpc is false)"
  type        = string
  default     = ""

  validation {
    condition     = var.custom_vpc_id == "" || can(regex("^vpc-[a-zA-Z0-9]+$", var.custom_vpc_id))
    error_message = "Custom VPC ID must be empty or a valid VPC identifier starting with 'vpc-'."
  }
}

variable "custom_subnet_ids" {
  description = "Custom subnet IDs to use for RDS deployment (when use_default_vpc is false)"
  type        = list(string)
  default     = []

  validation {
    condition = length(var.custom_subnet_ids) == 0 || (
      length(var.custom_subnet_ids) >= 2 &&
      alltrue([for id in var.custom_subnet_ids : can(regex("^subnet-[a-zA-Z0-9]+$", id))])
    )
    error_message = "Custom subnet IDs must be empty or a list of at least 2 valid subnet identifiers starting with 'subnet-'."
  }
}

# ---------------------------------------------------------------------------
# Security Configuration Variables
# ---------------------------------------------------------------------------

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the database through VPC Lattice"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

# ---------------------------------------------------------------------------
# Cost Optimization Variables
# ---------------------------------------------------------------------------

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades for RDS"
  type        = bool
  default     = true
}

variable "preferred_backup_window" {
  description = "Preferred backup window for RDS instance"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.preferred_backup_window))
    error_message = "Preferred backup window must be in the format HH:MM-HH:MM (24-hour format)."
  }
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window for RDS instance"
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "Preferred maintenance window must be in the format day:HH:MM-day:HH:MM."
  }
}