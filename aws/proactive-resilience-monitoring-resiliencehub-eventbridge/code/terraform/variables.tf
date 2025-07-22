# Variables for AWS Resilience Hub and EventBridge Monitoring Infrastructure

#------------------------------------------------------------------------------
# General Configuration
#------------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "resilience-demo"
  
  validation {
    condition     = length(var.name_prefix) <= 20 && length(var.name_prefix) >= 3
    error_message = "Name prefix must be between 3 and 20 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "resilience-monitoring"
    ManagedBy = "terraform"
  }
}

#------------------------------------------------------------------------------
# Application Configuration
#------------------------------------------------------------------------------

variable "app_name" {
  description = "Name of the application for resilience monitoring"
  type        = string
  default     = "demo-application"
  
  validation {
    condition     = length(var.app_name) <= 50 && length(var.app_name) >= 3
    error_message = "Application name must be between 3 and 50 characters."
  }
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.public_subnet_1_cidr, 0))
    error_message = "Public subnet 1 CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for the second private subnet (for RDS Multi-AZ)"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.private_subnet_2_cidr, 0))
    error_message = "Private subnet 2 CIDR must be a valid IPv4 CIDR block."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access to EC2 instances (leave empty to disable SSH access)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.allowed_ssh_cidr == "" || can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Allowed SSH CIDR must be empty or a valid IPv4 CIDR block."
  }
}

#------------------------------------------------------------------------------
# EC2 Configuration
#------------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the demo application"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t2.micro", "t2.small", "t2.medium", "t2.large",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type suitable for demo workloads."
  }
}

#------------------------------------------------------------------------------
# RDS Configuration
#------------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class for the demo database"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition = contains([
      "db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large",
      "db.t2.micro", "db.t2.small", "db.t2.medium", "db.t2.large",
      "db.m5.large", "db.m5.xlarge", "db.r5.large"
    ], var.db_instance_class)
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "mysql_version" {
  description = "MySQL engine version for RDS instance"
  type        = string
  default     = "8.0"
  
  validation {
    condition     = contains(["8.0", "5.7"], var.mysql_version)
    error_message = "MySQL version must be 8.0 or 5.7."
  }
}

variable "database_name" {
  description = "Name of the MySQL database to create"
  type        = string
  default     = "resiliencedb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "database_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  
  validation {
    condition     = length(var.database_username) >= 1 && length(var.database_username) <= 16
    error_message = "Database username must be between 1 and 16 characters."
  }
}

variable "database_password" {
  description = "Master password for the RDS instance (use AWS Secrets Manager in production)"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
  
  validation {
    condition     = length(var.database_password) >= 8 && length(var.database_password) <= 41
    error_message = "Database password must be between 8 and 41 characters."
  }
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9!@#$%^&*()_+=-]*$", var.database_password))
    error_message = "Database password contains invalid characters."
  }
}

#------------------------------------------------------------------------------
# Resilience Hub Configuration
#------------------------------------------------------------------------------

variable "resilience_tier" {
  description = "Resilience policy tier"
  type        = string
  default     = "MissionCritical"
  
  validation {
    condition = contains([
      "MissionCritical", "Critical", "Important", 
      "CoreServices", "NonCritical", "NotApplicable"
    ], var.resilience_tier)
    error_message = "Resilience tier must be one of: MissionCritical, Critical, Important, CoreServices, NonCritical, NotApplicable."
  }
}

variable "az_rto_minutes" {
  description = "Recovery Time Objective for Availability Zone failures (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.az_rto_minutes > 0 && var.az_rto_minutes <= 1440
    error_message = "AZ RTO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "az_rpo_minutes" {
  description = "Recovery Point Objective for Availability Zone failures (in minutes)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.az_rpo_minutes > 0 && var.az_rpo_minutes <= 1440
    error_message = "AZ RPO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "hardware_rto_minutes" {
  description = "Recovery Time Objective for hardware failures (in minutes)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.hardware_rto_minutes > 0 && var.hardware_rto_minutes <= 1440
    error_message = "Hardware RTO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "hardware_rpo_minutes" {
  description = "Recovery Point Objective for hardware failures (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.hardware_rpo_minutes > 0 && var.hardware_rpo_minutes <= 1440
    error_message = "Hardware RPO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "software_rto_minutes" {
  description = "Recovery Time Objective for software failures (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.software_rto_minutes > 0 && var.software_rto_minutes <= 1440
    error_message = "Software RTO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "software_rpo_minutes" {
  description = "Recovery Point Objective for software failures (in minutes)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.software_rpo_minutes > 0 && var.software_rpo_minutes <= 1440
    error_message = "Software RPO must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "region_rto_minutes" {
  description = "Recovery Time Objective for regional failures (in minutes)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.region_rto_minutes > 0 && var.region_rto_minutes <= 2880
    error_message = "Region RTO must be between 1 and 2880 minutes (48 hours)."
  }
}

variable "region_rpo_minutes" {
  description = "Recovery Point Objective for regional failures (in minutes)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.region_rpo_minutes > 0 && var.region_rpo_minutes <= 2880
    error_message = "Region RPO must be between 1 and 2880 minutes (48 hours)."
  }
}

#------------------------------------------------------------------------------
# Monitoring and Alerting Configuration
#------------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address for resilience alerts (leave empty to skip email notifications)"
  type        = string
  default     = ""
  
  validation {
    condition = var.alert_email == "" || can(regex(
      "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", 
      var.alert_email
    ))
    error_message = "Alert email must be empty or a valid email address."
  }
}

variable "critical_resilience_threshold" {
  description = "Critical threshold for resilience score (below this triggers critical alerts)"
  type        = number
  default     = 70
  
  validation {
    condition     = var.critical_resilience_threshold >= 0 && var.critical_resilience_threshold <= 100
    error_message = "Critical resilience threshold must be between 0 and 100."
  }
}

variable "warning_resilience_threshold" {
  description = "Warning threshold for resilience score (below this triggers warning alerts)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.warning_resilience_threshold >= 0 && var.warning_resilience_threshold <= 100
    error_message = "Warning resilience threshold must be between 0 and 100."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

#------------------------------------------------------------------------------
# Lambda Configuration
#------------------------------------------------------------------------------

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

#------------------------------------------------------------------------------
# Feature Flags
#------------------------------------------------------------------------------

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "enable_config_recorder" {
  description = "Enable AWS Config for compliance monitoring"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Cost Optimization
#------------------------------------------------------------------------------

variable "use_spot_instances" {
  description = "Use Spot instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain RDS automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.rds_backup_retention_days >= 1 && var.rds_backup_retention_days <= 35
    error_message = "RDS backup retention must be between 1 and 35 days."
  }
}