# Variables for Hybrid Identity Management with AWS Directory Service

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format of 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
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
  default     = "hybrid-identity"

  validation {
    condition = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]

  validation {
    condition = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

# Directory Service Configuration
variable "directory_name" {
  description = "Name for the AWS Managed Microsoft AD directory"
  type        = string
  default     = "corp.local"

  validation {
    condition = can(regex("^[a-z][a-z0-9.-]*\\.[a-z]{2,}$", var.directory_name))
    error_message = "Directory name must be a valid fully qualified domain name (FQDN)."
  }
}

variable "directory_password" {
  description = "Password for the directory administrator account"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = length(var.directory_password) >= 8 && length(var.directory_password) <= 64
    error_message = "Directory password must be between 8 and 64 characters."
  }
}

variable "directory_edition" {
  description = "Edition of AWS Managed Microsoft AD (Standard or Enterprise)"
  type        = string
  default     = "Standard"

  validation {
    condition = contains(["Standard", "Enterprise"], var.directory_edition)
    error_message = "Directory edition must be either 'Standard' or 'Enterprise'."
  }
}

variable "directory_description" {
  description = "Description for the AWS Managed Microsoft AD directory"
  type        = string
  default     = "Hybrid Identity Management Directory"
}

# WorkSpaces Configuration
variable "enable_workspaces" {
  description = "Enable Amazon WorkSpaces integration"
  type        = bool
  default     = true
}

variable "workspaces_bundle_id" {
  description = "WorkSpaces bundle ID for virtual desktops"
  type        = string
  default     = "wsb-bh8rsxt14" # Standard Windows 10 bundle
}

variable "enable_workdocs" {
  description = "Enable Amazon WorkDocs integration with WorkSpaces"
  type        = bool
  default     = true
}

variable "enable_self_service_permissions" {
  description = "Allow users to manage their own WorkSpaces"
  type        = bool
  default     = true
}

# RDS Configuration
variable "enable_rds" {
  description = "Enable RDS SQL Server with Directory Service integration"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "Instance class for RDS SQL Server"
  type        = string
  default     = "db.t3.medium"

  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.rds_instance_class))
    error_message = "RDS instance class must be in the format 'db.instance_family.size'."
  }
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS instance (GB)"
  type        = number
  default     = 200

  validation {
    condition = var.rds_allocated_storage >= 20 && var.rds_allocated_storage <= 65536
    error_message = "RDS allocated storage must be between 20 and 65536 GB."
  }
}

variable "rds_storage_type" {
  description = "Storage type for RDS instance"
  type        = string
  default     = "gp2"

  validation {
    condition = contains(["standard", "gp2", "gp3", "io1", "io2"], var.rds_storage_type)
    error_message = "RDS storage type must be one of: standard, gp2, gp3, io1, io2."
  }
}

variable "rds_engine_version" {
  description = "SQL Server engine version for RDS"
  type        = string
  default     = "15.00.4236.7.v1" # SQL Server 2019

  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.v[0-9]+$", var.rds_engine_version))
    error_message = "RDS engine version must be in the format 'major.minor.build.revision.vN'."
  }
}

variable "rds_backup_retention_period" {
  description = "Backup retention period for RDS instance (days)"
  type        = number
  default     = 7

  validation {
    condition = var.rds_backup_retention_period >= 0 && var.rds_backup_retention_period <= 35
    error_message = "RDS backup retention period must be between 0 and 35 days."
  }
}

variable "rds_backup_window" {
  description = "Preferred backup window for RDS instance"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.rds_backup_window))
    error_message = "RDS backup window must be in the format 'HH:MM-HH:MM'."
  }
}

variable "rds_maintenance_window" {
  description = "Preferred maintenance window for RDS instance"
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.rds_maintenance_window))
    error_message = "RDS maintenance window must be in the format 'ddd:HH:MM-ddd:HH:MM'."
  }
}

# Security Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for RDS"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Monitoring interval for RDS enhanced monitoring (seconds)"
  type        = number
  default     = 60

  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "enable_storage_encryption" {
  description = "Enable storage encryption for RDS instance"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for directory service auditing"
  type        = bool
  default     = true
}

# Trust Relationship Configuration
variable "enable_on_premises_trust" {
  description = "Enable trust relationship with on-premises Active Directory"
  type        = bool
  default     = false
}

variable "on_premises_domain_name" {
  description = "FQDN of on-premises Active Directory domain"
  type        = string
  default     = ""

  validation {
    condition = var.enable_on_premises_trust == false || can(regex("^[a-z][a-z0-9.-]*\\.[a-z]{2,}$", var.on_premises_domain_name))
    error_message = "On-premises domain name must be a valid FQDN when trust is enabled."
  }
}

variable "on_premises_dns_ips" {
  description = "List of DNS server IP addresses for on-premises domain"
  type        = list(string)
  default     = []

  validation {
    condition = var.enable_on_premises_trust == false || length(var.on_premises_dns_ips) > 0
    error_message = "On-premises DNS IPs must be provided when trust is enabled."
  }
}

variable "trust_password" {
  description = "Password for the trust relationship"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = var.enable_on_premises_trust == false || length(var.trust_password) >= 8
    error_message = "Trust password must be at least 8 characters when trust is enabled."
  }
}

variable "trust_direction" {
  description = "Direction of trust relationship (One-Way: Outgoing, One-Way: Incoming, Two-Way)"
  type        = string
  default     = "Two-Way"

  validation {
    condition = contains(["One-Way: Outgoing", "One-Way: Incoming", "Two-Way"], var.trust_direction)
    error_message = "Trust direction must be one of: 'One-Way: Outgoing', 'One-Way: Incoming', 'Two-Way'."
  }
}

# Test User Configuration
variable "create_test_users" {
  description = "Create test users in the directory for validation"
  type        = bool
  default     = true
}

variable "test_users" {
  description = "List of test users to create"
  type = list(object({
    username    = string
    given_name  = string
    surname     = string
    email       = string
    description = string
  }))
  default = [
    {
      username    = "testuser1"
      given_name  = "Test"
      surname     = "User1"
      email       = "testuser1@example.com"
      description = "Test user for hybrid identity validation"
    },
    {
      username    = "testuser2"
      given_name  = "Test"
      surname     = "User2"
      email       = "testuser2@example.com"
      description = "Test user for WorkSpaces validation"
    }
  ]
}

# Default tags applied to all resources
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "hybrid-identity-management"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "hybrid-identity-management"
  }
}