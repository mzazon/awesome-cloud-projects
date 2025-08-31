# Variables for cross-account database sharing with VPC Lattice and RDS

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "consumer_account_id" {
  description = "AWS Account ID that will consume the shared database (Account B)"
  type        = string
  
  validation {
    condition = can(regex("^[0-9]{12}$", var.consumer_account_id))
    error_message = "Consumer account ID must be a 12-digit number."
  }
}

variable "external_id" {
  description = "External ID for cross-account role trust policy"
  type        = string
  default     = "unique-external-id-12345"
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "db_instance_class" {
  description = "RDS database instance class"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition = can(regex("^db\\.(t3|t4g|m5|m6i|r5|r6i)\\.(micro|small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge)$", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_engine" {
  description = "RDS database engine"
  type        = string
  default     = "mysql"
  
  validation {
    condition = contains(["mysql", "postgres", "mariadb"], var.db_engine)
    error_message = "Database engine must be one of: mysql, postgres, mariadb."
  }
}

variable "db_engine_version" {
  description = "RDS database engine version"
  type        = string
  default     = "8.0"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS database in GB"
  type        = number
  default     = 20
  
  validation {
    condition = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
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

variable "db_master_username" {
  description = "Master username for RDS database"
  type        = string
  default     = "admin"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_master_password" {
  description = "Master password for RDS database"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.db_master_password == null || (length(var.db_master_password) >= 8 && length(var.db_master_password) <= 128)
    error_message = "Master password must be between 8 and 128 characters when specified."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS database"
  type        = bool
  default     = false
}

variable "enable_storage_encryption" {
  description = "Enable storage encryption for RDS database"
  type        = bool
  default     = true
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ deployment for RDS database"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring for RDS database"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "create_random_password" {
  description = "Create a random password for the database master user"
  type        = bool
  default     = true
}

variable "resource_share_name" {
  description = "Name for the AWS RAM resource share"
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}