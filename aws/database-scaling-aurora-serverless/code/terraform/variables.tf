# Variables for Aurora Serverless v2 Database Scaling Infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "aurora-serverless"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Aurora Cluster Configuration
variable "cluster_identifier" {
  description = "Identifier for the Aurora cluster (will have random suffix added)"
  type        = string
  default     = "aurora-serverless"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_identifier))
    error_message = "Cluster identifier must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "engine_version" {
  description = "Aurora MySQL engine version"
  type        = string
  default     = "8.0.mysql_aurora.3.02.0"
}

variable "database_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "ecommerce"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.master_username) >= 1 && length(var.master_username) <= 16
    error_message = "Master username must be between 1 and 16 characters."
  }
}

variable "master_password" {
  description = "Master password for the Aurora cluster (minimum 8 characters)"
  type        = string
  default     = "ServerlessTest123!"
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "Master password must be at least 8 characters long."
  }
}

# Serverless v2 Scaling Configuration
variable "serverless_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACUs) for scaling"
  type        = number
  default     = 0.5

  validation {
    condition     = var.serverless_min_capacity >= 0.5 && var.serverless_min_capacity <= 128
    error_message = "Minimum capacity must be between 0.5 and 128 ACUs."
  }
}

variable "serverless_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACUs) for scaling"
  type        = number
  default     = 16

  validation {
    condition     = var.serverless_max_capacity >= 0.5 && var.serverless_max_capacity <= 128
    error_message = "Maximum capacity must be between 0.5 and 128 ACUs."
  }
}

# Network Configuration
variable "use_existing_vpc" {
  description = "Whether to use an existing VPC (true) or create a new one (false)"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (if use_existing_vpc is true)"
  type        = string
  default     = null
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs to use (if use_existing_vpc is true)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (used only if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (used only if creating new VPC)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for Aurora clusters."
  }
}

# Monitoring and Backup Configuration
variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for Aurora instances"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Retention period for Performance Insights data (days)"
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 or 731 days."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch log exports"
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["error", "general", "slowquery"]

  validation {
    condition = alltrue([
      for log_type in var.enabled_cloudwatch_logs_exports :
      contains(["error", "general", "slowquery"], log_type)
    ])
    error_message = "Log types must be one of: error, general, slowquery."
  }
}

# CloudWatch Alarm Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "high_acu_threshold" {
  description = "Threshold for high ACU utilization alarm"
  type        = number
  default     = 12

  validation {
    condition     = var.high_acu_threshold > 0 && var.high_acu_threshold <= 128
    error_message = "High ACU threshold must be between 0 and 128."
  }
}

variable "low_acu_threshold" {
  description = "Threshold for low ACU utilization alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.low_acu_threshold >= 0.5 && var.low_acu_threshold <= 128
    error_message = "Low ACU threshold must be between 0.5 and 128."
  }
}

variable "alarm_notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = null

  validation {
    condition = var.alarm_notification_email == null || can(regex(
      "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
      var.alarm_notification_email
    ))
    error_message = "Email address must be valid format or null."
  }
}

# Security Configuration
variable "deletion_protection" {
  description = "Enable deletion protection for the Aurora cluster"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting cluster (not recommended for production)"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the Aurora cluster"
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Read Replica Configuration
variable "create_read_replica" {
  description = "Whether to create a read replica instance"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}