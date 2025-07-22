# ==============================================================================
# Input Variables for Modular Multi-Tier Architecture
# These variables allow customization of the infrastructure deployment
# across different environments and configurations.
# ==============================================================================

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"
    ], var.aws_region)
    error_message = "AWS region must be a valid AWS region."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource tagging and naming"
  type        = string
  default     = "webapp"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
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

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (set to false for cost savings in development)"
  type        = bool
  default     = true
}

variable "enable_bastion_host" {
  description = "Enable bastion host for SSH access to private instances"
  type        = bool
  default     = false
}

variable "enable_database_backup" {
  description = "Enable automated database backups"
  type        = bool
  default     = true
}

variable "database_deletion_protection" {
  description = "Enable deletion protection for the database"
  type        = bool
  default     = null # Will use environment-specific default
}

variable "load_balancer_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = null # Will use environment-specific default
}

variable "custom_instance_type" {
  description = "Custom EC2 instance type (overrides environment default)"
  type        = string
  default     = null
  
  validation {
    condition = var.custom_instance_type == null || can(regex("^[a-z][0-9]+[a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.custom_instance_type))
    error_message = "Instance type must be a valid EC2 instance type (e.g., t3.micro, m5.large)."
  }
}

variable "custom_db_instance_class" {
  description = "Custom RDS instance class (overrides environment default)"
  type        = string
  default     = null
  
  validation {
    condition = var.custom_db_instance_class == null || can(regex("^db\\.[a-z][0-9]+[a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.custom_db_instance_class))
    error_message = "DB instance class must be a valid RDS instance class (e.g., db.t3.micro, db.r5.large)."
  }
}

variable "auto_scaling_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = null
  
  validation {
    condition = var.auto_scaling_min_size == null || (var.auto_scaling_min_size >= 0 && var.auto_scaling_min_size <= 100)
    error_message = "Minimum size must be between 0 and 100."
  }
}

variable "auto_scaling_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = null
  
  validation {
    condition = var.auto_scaling_max_size == null || (var.auto_scaling_max_size >= 1 && var.auto_scaling_max_size <= 100)
    error_message = "Maximum size must be between 1 and 100."
  }
}

variable "auto_scaling_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = null
  
  validation {
    condition = var.auto_scaling_desired_capacity == null || (var.auto_scaling_desired_capacity >= 0 && var.auto_scaling_desired_capacity <= 100)
    error_message = "Desired capacity must be between 0 and 100."
  }
}

variable "database_allocated_storage" {
  description = "Allocated storage for the RDS instance in GB"
  type        = number
  default     = null
  
  validation {
    condition = var.database_allocated_storage == null || (var.database_allocated_storage >= 20 && var.database_allocated_storage <= 65536)
    error_message = "Database storage must be between 20 and 65536 GB."
  }
}

variable "enable_database_multi_az" {
  description = "Enable Multi-AZ deployment for the database"
  type        = bool
  default     = null # Will use environment-specific default
}

variable "database_backup_retention_period" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7
  
  validation {
    condition = var.database_backup_retention_period >= 0 && var.database_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for the database"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = null # Will use environment-specific default
  
  validation {
    condition = var.cloudwatch_log_retention_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the supported CloudWatch values."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = length(var.additional_tags) <= 50
    error_message = "Cannot specify more than 50 additional tags."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the load balancer (empty list allows all)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed SSH access to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([for cidr in var.ssh_allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "database_engine_version" {
  description = "MySQL engine version for the RDS instance"
  type        = string
  default     = "8.0.35"
  
  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.database_engine_version))
    error_message = "Database engine version must be in format X.Y.Z (e.g., 8.0.35)."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Grace period for Auto Scaling Group health checks (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 7200
    error_message = "Health check grace period must be between 0 and 7200 seconds."
  }
}

variable "target_group_deregistration_delay" {
  description = "Time to wait before deregistering targets (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.target_group_deregistration_delay >= 0 && var.target_group_deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}