# General configuration variables
variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "multitenant-lattice"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

# VPC Lattice configuration
variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = ""
}

variable "auth_type" {
  description = "Authentication type for VPC Lattice service network"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.auth_type)
    error_message = "Auth type must be either AWS_IAM or NONE."
  }
}

# VPC configuration
variable "vpc_id" {
  description = "VPC ID to associate with the service network. If not provided, will use default VPC"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for RDS deployment. If not provided, will use subnets from the VPC"
  type        = list(string)
  default     = []
}

# RDS configuration
variable "db_instance_class" {
  description = "RDS instance class for the shared database"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition     = can(regex("^db\\.", var.db_instance_class))
    error_message = "DB instance class must start with 'db.'."
  }
}

variable "db_engine" {
  description = "Database engine for RDS instance"
  type        = string
  default     = "mysql"
  
  validation {
    condition     = contains(["mysql", "mariadb", "postgres", "aurora-mysql", "aurora-postgresql"], var.db_engine)
    error_message = "Supported engines: mysql, mariadb, postgres, aurora-mysql, aurora-postgresql."
  }
}

variable "db_engine_version" {
  description = "Database engine version. If not specified, uses default for the engine"
  type        = string
  default     = ""
}

variable "db_allocated_storage" {
  description = "Allocated storage size in GB for RDS instance"
  type        = number
  default     = 20
  
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_storage_encrypted" {
  description = "Enable encryption for RDS instance storage"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days for RDS instance"
  type        = number
  default     = 7
  
  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "db_master_username" {
  description = "Master username for RDS instance"
  type        = string
  default     = "admin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.db_master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters."
  }
}

variable "db_manage_master_user_password" {
  description = "Set to true to allow RDS to manage the master user password through AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "db_master_user_password" {
  description = "Master password for RDS instance. Only used if db_manage_master_user_password is false"
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_port" {
  description = "Port for the RDS instance"
  type        = number
  default     = 3306
  
  validation {
    condition     = var.db_port > 1024 && var.db_port < 65536
    error_message = "Database port must be between 1024 and 65535."
  }
}

variable "db_publicly_accessible" {
  description = "Make RDS instance publicly accessible"
  type        = bool
  default     = false
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS instance"
  type        = bool
  default     = false
}

# AWS RAM configuration
variable "ram_share_principals" {
  description = "List of AWS account IDs or organization IDs to share resources with"
  type        = list(string)
  default     = []
}

variable "ram_allow_external_principals" {
  description = "Allow sharing with principals outside of your organization"
  type        = bool
  default     = false
}

# Team configuration for IAM roles
variable "tenant_teams" {
  description = "List of tenant teams for IAM role creation"
  type        = list(string)
  default     = ["TeamA", "TeamB"]
  
  validation {
    condition     = length(var.tenant_teams) > 0
    error_message = "At least one tenant team must be specified."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP CIDR ranges allowed to access the service network"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# CloudTrail configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_include_global_service_events" {
  description = "Include global service events in CloudTrail"
  type        = bool
  default     = true
}

variable "cloudtrail_is_multi_region_trail" {
  description = "Make CloudTrail a multi-region trail"
  type        = bool
  default     = true
}

variable "cloudtrail_enable_log_file_validation" {
  description = "Enable log file validation for CloudTrail"
  type        = bool
  default     = true
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs. If not provided, will be auto-generated"
  type        = string
  default     = ""
}

# Resource configuration
variable "resource_config_port_ranges" {
  description = "Port ranges for VPC Lattice resource configuration"
  type        = list(string)
  default     = ["3306"]
}

variable "resource_config_protocol" {
  description = "Protocol for VPC Lattice resource configuration"
  type        = string
  default     = "TCP"
  
  validation {
    condition     = contains(["TCP", "UDP", "ICMP"], var.resource_config_protocol)
    error_message = "Protocol must be TCP, UDP, or ICMP."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}