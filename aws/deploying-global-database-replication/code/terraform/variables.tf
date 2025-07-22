# Variables for Aurora Global Database Infrastructure
# This file defines all configurable parameters for the global database deployment

# Environment and Naming Variables
variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "ecommerce-global"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary AWS region for the Aurora Global Database"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region identifier."
  }
}

variable "secondary_region_eu" {
  description = "Secondary AWS region for European Aurora cluster"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.secondary_region_eu))
    error_message = "Secondary EU region must be a valid AWS region identifier."
  }
}

variable "secondary_region_asia" {
  description = "Secondary AWS region for Asian Aurora cluster"
  type        = string
  default     = "ap-southeast-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.secondary_region_asia))
    error_message = "Secondary Asia region must be a valid AWS region identifier."
  }
}

# Database Configuration
variable "db_engine" {
  description = "Database engine for Aurora Global Database"
  type        = string
  default     = "aurora-mysql"
  
  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.db_engine)
    error_message = "Database engine must be either aurora-mysql or aurora-postgresql."
  }
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0.mysql_aurora.3.02.0"
  
  validation {
    condition     = length(var.engine_version) > 0
    error_message = "Engine version must be specified."
  }
}

variable "db_instance_class" {
  description = "Database instance class for Aurora clusters"
  type        = string
  default     = "db.r5.large"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "Database instance class must be a valid Aurora instance class."
  }
}

variable "master_username" {
  description = "Master username for Aurora Global Database"
  type        = string
  default     = "globaladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]+$", var.master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "master_password" {
  description = "Master password for Aurora Global Database (use AWS Secrets Manager in production)"
  type        = string
  default     = null
  sensitive   = true
  
  validation {
    condition     = var.master_password == null || length(var.master_password) >= 8
    error_message = "Master password must be at least 8 characters long."
  }
}

variable "manage_master_user_password" {
  description = "Whether to manage master user password with AWS Secrets Manager"
  type        = bool
  default     = true
}

# Database Instance Configuration
variable "create_reader_instances" {
  description = "Whether to create reader instances in each cluster"
  type        = bool
  default     = true
}

variable "reader_instance_count" {
  description = "Number of reader instances to create per cluster"
  type        = number
  default     = 1
  
  validation {
    condition     = var.reader_instance_count >= 0 && var.reader_instance_count <= 5
    error_message = "Reader instance count must be between 0 and 5."
  }
}

# Write Forwarding Configuration
variable "enable_global_write_forwarding" {
  description = "Enable write forwarding for secondary clusters"
  type        = bool
  default     = true
}

# Backup and Maintenance Configuration
variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Preferred backup window in UTC"
  type        = string
  default     = "07:00-09:00"
  
  validation {
    condition = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.preferred_backup_window))
    error_message = "Preferred backup window must be in format HH:MM-HH:MM."
  }
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window in UTC"
  type        = string
  default     = "sun:09:00-sun:11:00"
  
  validation {
    condition = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.preferred_maintenance_window))
    error_message = "Preferred maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

# Monitoring Configuration
variable "enable_performance_insights" {
  description = "Enable Performance Insights for Aurora instances"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be either 7 or 731 days."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Aurora instances"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

# Security Configuration
variable "deletion_protection" {
  description = "Enable deletion protection for Aurora clusters"
  type        = bool
  default     = true
}

variable "storage_encrypted" {
  description = "Enable storage encryption for Aurora clusters"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for Aurora cluster encryption (optional)"
  type        = string
  default     = null
}

# CloudWatch Dashboard Configuration
variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for global database monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = null
}

# Networking Configuration
variable "db_subnet_group_name" {
  description = "Name of existing DB subnet group to use (optional)"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs to associate with Aurora clusters"
  type        = list(string)
  default     = []
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 10
    error_message = "Maximum of 10 additional tags allowed."
  }
}

# Auto Scaling Configuration
variable "enable_auto_scaling" {
  description = "Enable auto scaling for Aurora clusters"
  type        = bool
  default     = false
}

variable "auto_scaling_min_capacity" {
  description = "Minimum capacity for auto scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.auto_scaling_min_capacity >= 1
    error_message = "Auto scaling minimum capacity must be at least 1."
  }
}

variable "auto_scaling_max_capacity" {
  description = "Maximum capacity for auto scaling"
  type        = number
  default     = 5
  
  validation {
    condition     = var.auto_scaling_max_capacity >= var.auto_scaling_min_capacity
    error_message = "Auto scaling maximum capacity must be greater than or equal to minimum capacity."
  }
}

variable "auto_scaling_target_cpu" {
  description = "Target CPU utilization for auto scaling"
  type        = number
  default     = 70
  
  validation {
    condition     = var.auto_scaling_target_cpu >= 10 && var.auto_scaling_target_cpu <= 90
    error_message = "Auto scaling target CPU must be between 10 and 90 percent."
  }
}