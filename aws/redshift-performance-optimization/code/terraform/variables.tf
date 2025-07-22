# AWS region for resource deployment
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Environment identifier for resource naming and tagging
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Redshift cluster configuration
variable "cluster_identifier" {
  description = "Unique identifier for the Redshift cluster"
  type        = string
  default     = "redshift-performance-cluster"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_identifier))
    error_message = "Cluster identifier must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "node_type" {
  description = "The node type for the Redshift cluster"
  type        = string
  default     = "dc2.large"
  validation {
    condition = contains(["dc2.large", "dc2.8xlarge", "ds2.xlarge", "ds2.8xlarge", "ra3.xlplus", "ra3.4xlarge", "ra3.16xlarge"], var.node_type)
    error_message = "Node type must be a valid Redshift node type."
  }
}

variable "number_of_nodes" {
  description = "Number of compute nodes in the Redshift cluster"
  type        = number
  default     = 2
  validation {
    condition = var.number_of_nodes >= 1 && var.number_of_nodes <= 128
    error_message = "Number of nodes must be between 1 and 128."
  }
}

variable "database_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "performance_db"
  validation {
    condition = can(regex("^[a-z][a-z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "master_username" {
  description = "Master username for the Redshift cluster"
  type        = string
  default     = "admin"
  validation {
    condition = can(regex("^[a-z][a-z0-9_]*$", var.master_username))
    error_message = "Master username must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

# VPC configuration for Redshift cluster
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  validation {
    condition = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for Redshift."
  }
}

# SNS notification configuration
variable "notification_email" {
  description = "Email address for performance alert notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# CloudWatch monitoring configuration
variable "enable_performance_insights" {
  description = "Enable Redshift Performance Insights"
  type        = bool
  default     = true
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 80
  validation {
    condition = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 1 and 100."
  }
}

variable "queue_length_threshold" {
  description = "Queue length threshold for CloudWatch alarm"
  type        = number
  default     = 10
  validation {
    condition = var.queue_length_threshold > 0
    error_message = "Queue length threshold must be greater than 0."
  }
}

# Lambda function configuration
variable "maintenance_schedule" {
  description = "Cron expression for automated maintenance schedule"
  type        = string
  default     = "cron(0 2 * * ? *)"
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.maintenance_schedule))
    error_message = "Maintenance schedule must be a valid cron expression."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda maintenance function in seconds"
  type        = number
  default     = 300
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

# Security configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Redshift cluster"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  validation {
    condition = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

variable "enable_logging" {
  description = "Enable Redshift audit logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}