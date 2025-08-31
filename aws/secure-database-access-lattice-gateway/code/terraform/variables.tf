# Input variables for the secure database access with VPC Lattice Resource Gateway

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "lattice-db-access"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,}$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs in different AZs for multi-AZ deployment"
  type        = list(string)
  
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets in different AZs are required for high availability."
  }
  
  validation {
    condition = alltrue([
      for subnet_id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,}$", subnet_id))
    ])
    error_message = "All subnet IDs must be valid AWS subnet identifiers."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC for security group rules"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "VPC CIDR block must be a valid IPv4 CIDR."
  }
}

variable "consumer_account_id" {
  description = "AWS Account ID of the consumer account that will access the shared database"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.consumer_account_id))
    error_message = "Consumer account ID must be a 12-digit AWS account ID."
  }
}

variable "db_instance_class" {
  description = "RDS instance class for the shared database"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition = contains([
      "db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large",
      "db.m5.large", "db.m5.xlarge", "db.m5.2xlarge", "db.m5.4xlarge",
      "db.r5.large", "db.r5.xlarge", "db.r5.2xlarge", "db.r5.4xlarge"
    ], var.db_instance_class)
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_engine" {
  description = "Database engine for the RDS instance"
  type        = string
  default     = "mysql"
  
  validation {
    condition = contains([
      "mysql", "postgres", "mariadb"
    ], var.db_engine)
    error_message = "Database engine must be one of: mysql, postgres, mariadb."
  }
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  
  validation {
    condition     = length(var.db_username) >= 3 && length(var.db_username) <= 16
    error_message = "Database username must be between 3 and 16 characters."
  }
}

variable "db_password" {
  description = "Master password for the RDS instance (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition = var.db_password == "" || (
      length(var.db_password) >= 8 && 
      length(var.db_password) <= 128 &&
      can(regex("[A-Z]", var.db_password)) &&
      can(regex("[a-z]", var.db_password)) &&
      can(regex("[0-9]", var.db_password))
    )
    error_message = "Password must be 8-128 characters with uppercase, lowercase, and numbers, or leave empty for auto-generation."
  }
}

variable "db_port" {
  description = "Database port number"
  type        = number
  default     = 3306
  
  validation {
    condition     = var.db_port > 1024 && var.db_port < 65536
    error_message = "Database port must be between 1025 and 65535."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for RDS instance"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS instance"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Interval for enhanced monitoring (0, 1, 5, 10, 15, 30, 60 seconds)"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60 seconds."
  }
}

variable "enable_access_logs" {
  description = "Enable VPC Lattice access logs"
  type        = bool
  default     = true
}

variable "access_logs_s3_bucket" {
  description = "S3 bucket for VPC Lattice access logs (leave empty to create a new bucket)"
  type        = string
  default     = ""
}

variable "create_consumer_vpc_association" {
  description = "Create VPC association for consumer account (requires consumer account credentials)"
  type        = bool
  default     = false
}

variable "consumer_vpc_id" {
  description = "VPC ID in consumer account (only required if create_consumer_vpc_association is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.consumer_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,}$", var.consumer_vpc_id))
    error_message = "Consumer VPC ID must be empty or a valid AWS VPC identifier."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}