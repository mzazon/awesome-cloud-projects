# Input variables for RDS Multi-AZ Cross-Region Failover infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "primary_region" {
  description = "The primary AWS region for RDS deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "The secondary AWS region for cross-region read replica"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
  
  validation {
    condition = var.secondary_region != var.primary_region
    error_message = "Secondary region must be different from primary region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "db_instance_class" {
  description = "The instance class for RDS instances"
  type        = string
  default     = "db.r5.xlarge"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance type (e.g., db.r5.xlarge)."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "db_allocated_storage" {
  description = "The allocated storage size in GB"
  type        = number
  default     = 500
  
  validation {
    condition = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_master_username" {
  description = "The master username for the database"
  type        = string
  default     = "dbadmin"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_master_username))
    error_message = "Master username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "db_backup_retention_period" {
  description = "The number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition = var.db_backup_retention_period >= 1 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "db_backup_window" {
  description = "The preferred backup window"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.db_backup_window))
    error_message = "Backup window must be in HH:MM-HH:MM format."
  }
}

variable "db_maintenance_window" {
  description = "The preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.db_maintenance_window))
    error_message = "Maintenance window must be in ddd:HH:MM-ddd:HH:MM format."
  }
}

variable "primary_vpc_id" {
  description = "VPC ID for primary region RDS deployment"
  type        = string
  
  validation {
    condition = can(regex("^vpc-[a-f0-9]{8,17}$", var.primary_vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier."
  }
}

variable "primary_subnet_ids" {
  description = "List of subnet IDs in primary region for RDS subnet group"
  type        = list(string)
  
  validation {
    condition = length(var.primary_subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for Multi-AZ deployment."
  }
}

variable "secondary_vpc_id" {
  description = "VPC ID for secondary region RDS deployment"
  type        = string
  
  validation {
    condition = can(regex("^vpc-[a-f0-9]{8,17}$", var.secondary_vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier."
  }
}

variable "secondary_subnet_ids" {
  description = "List of subnet IDs in secondary region for RDS subnet group"
  type        = list(string)
  
  validation {
    condition = length(var.secondary_subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for read replica deployment."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All elements must be valid CIDR blocks."
  }
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for RDS instances"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 or 731 days."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instances"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch logs retention must be a valid retention period."
  }
}

variable "monitoring_interval" {
  description = "The interval for collecting enhanced monitoring metrics (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

variable "route53_hosted_zone_name" {
  description = "Route 53 hosted zone name for DNS failover"
  type        = string
  default     = "financial-db.internal"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.route53_hosted_zone_name))
    error_message = "Hosted zone name must be a valid domain name."
  }
}

variable "dns_record_name" {
  description = "DNS record name for database endpoint"
  type        = string
  default     = "db"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.dns_record_name))
    error_message = "DNS record name must contain only letters, numbers, and hyphens."
  }
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.dns_ttl >= 30 && var.dns_ttl <= 86400
    error_message = "DNS TTL must be between 30 and 86400 seconds."
  }
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures before considering endpoint unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

variable "connection_failure_threshold" {
  description = "CloudWatch alarm threshold for database connections"
  type        = number
  default     = 80
  
  validation {
    condition = var.connection_failure_threshold >= 1 && var.connection_failure_threshold <= 5000
    error_message = "Connection failure threshold must be between 1 and 5000."
  }
}

variable "replica_lag_threshold" {
  description = "CloudWatch alarm threshold for replica lag in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.replica_lag_threshold >= 60 && var.replica_lag_threshold <= 3600
    error_message = "Replica lag threshold must be between 60 and 3600 seconds."
  }
}

variable "sns_notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_notification_email))
    error_message = "SNS notification email must be a valid email address or empty string."
  }
}

variable "enable_automated_backup_replication" {
  description = "Enable automated backup replication to secondary region"
  type        = bool
  default     = true
}

variable "backup_replication_retention_period" {
  description = "Backup replication retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = var.backup_replication_retention_period >= 1 && var.backup_replication_retention_period <= 35
    error_message = "Backup replication retention period must be between 1 and 35 days."
  }
}