# Common variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "rds-proxy"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "RDS Proxy Demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

# Network variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for RDS."
  }
}

# Database variables
variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "testdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.db_username) >= 1 && length(var.db_username) <= 16
    error_message = "Database username must be between 1 and 16 characters."
  }
}

variable "db_password" {
  description = "Master password for the database"
  type        = string
  default     = "MySecurePassword123!"
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition = contains([
      "db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large",
      "db.t4g.micro", "db.t4g.small", "db.t4g.medium", "db.t4g.large",
      "db.m5.large", "db.m5.xlarge", "db.m5.2xlarge"
    ], var.db_instance_class)
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for RDS instance (GB)"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

# RDS Proxy variables
variable "proxy_idle_client_timeout" {
  description = "Idle client timeout for RDS Proxy (seconds)"
  type        = number
  default     = 900

  validation {
    condition     = var.proxy_idle_client_timeout >= 1 && var.proxy_idle_client_timeout <= 28800
    error_message = "Idle client timeout must be between 1 and 28800 seconds."
  }
}

variable "proxy_max_connections_percent" {
  description = "Maximum connections as percentage of database max connections"
  type        = number
  default     = 75

  validation {
    condition     = var.proxy_max_connections_percent >= 1 && var.proxy_max_connections_percent <= 100
    error_message = "Max connections percent must be between 1 and 100."
  }
}

variable "proxy_max_idle_connections_percent" {
  description = "Maximum idle connections as percentage of max connections"
  type        = number
  default     = 25

  validation {
    condition     = var.proxy_max_idle_connections_percent >= 0 && var.proxy_max_idle_connections_percent <= 100
    error_message = "Max idle connections percent must be between 0 and 100."
  }
}

variable "proxy_debug_logging" {
  description = "Enable debug logging for RDS Proxy"
  type        = bool
  default     = true
}

# Lambda variables
variable "create_lambda_test_function" {
  description = "Whether to create Lambda test function"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Lambda function timeout (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}