# General Configuration Variables
variable "aws_region" {
  description = "AWS region for primary resources"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS region for disaster recovery resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "rds-backup-recovery"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Database Configuration Variables
variable "db_engine" {
  description = "Database engine type"
  type        = string
  default     = "mysql"
  
  validation {
    condition     = contains(["mysql", "postgres", "oracle-ee", "oracle-se2", "sqlserver-ee", "sqlserver-se", "sqlserver-ex", "sqlserver-web"], var.db_engine)
    error_message = "Database engine must be a valid RDS engine type."
  }
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20
  
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_storage_type" {
  description = "Storage type for the RDS instance"
  type        = string
  default     = "gp2"
  
  validation {
    condition     = contains(["standard", "gp2", "gp3", "io1", "io2"], var.db_storage_type)
    error_message = "Storage type must be one of: standard, gp2, gp3, io1, io2."
  }
}

variable "db_username" {
  description = "Username for the RDS instance"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Password for the RDS instance"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

# Backup Configuration Variables
variable "backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "dr_backup_retention_period" {
  description = "The days to retain backups in DR region"
  type        = number
  default     = 14
  
  validation {
    condition     = var.dr_backup_retention_period >= 1 && var.dr_backup_retention_period <= 35
    error_message = "DR backup retention period must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "The daily time range during which automated backups are created"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]-([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in the format HH:MM-HH:MM."
  }
}

variable "maintenance_window" {
  description = "The weekly time range during which system maintenance can occur"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition     = can(regex("^(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]-(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in the format ddd:hh:mm-ddd:hh:mm."
  }
}

variable "daily_backup_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.daily_backup_retention_days >= 1 && var.daily_backup_retention_days <= 365
    error_message = "Daily backup retention must be between 1 and 365 days."
  }
}

variable "weekly_backup_retention_days" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 90
  
  validation {
    condition     = var.weekly_backup_retention_days >= 1 && var.weekly_backup_retention_days <= 365
    error_message = "Weekly backup retention must be between 1 and 365 days."
  }
}

variable "cold_storage_transition_days" {
  description = "Number of days after which to transition backups to cold storage"
  type        = number
  default     = 7
  
  validation {
    condition     = var.cold_storage_transition_days >= 1 && var.cold_storage_transition_days <= 100
    error_message = "Cold storage transition must be between 1 and 100 days."
  }
}

# Notification Configuration Variables
variable "enable_backup_notifications" {
  description = "Enable SNS notifications for backup events"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for backup notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Security Configuration Variables
variable "enable_storage_encryption" {
  description = "Enable encryption for RDS storage"
  type        = bool
  default     = true
}

variable "enable_backup_encryption" {
  description = "Enable encryption for backup storage"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = true
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = true
}

# Network Configuration Variables
variable "vpc_id" {
  description = "VPC ID for RDS deployment (optional, uses default VPC if not specified)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for RDS deployment (optional, uses default subnets if not specified)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the RDS instance"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# Resource Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}