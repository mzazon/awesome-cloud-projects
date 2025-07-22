# Variables for Aurora Serverless v2 Cost Optimization Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1'."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "cluster_name_prefix" {
  description = "Prefix for Aurora cluster name (random suffix will be added)"
  type        = string
  default     = "aurora-sv2-cost-opt"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.cluster_name_prefix))
    error_message = "Cluster name prefix must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "master_password" {
  description = "Master password for Aurora cluster (if not using manage_master_user_password)"
  type        = string
  default     = null
  sensitive   = true
  
  validation {
    condition = var.master_password == null || length(var.master_password) >= 8
    error_message = "Master password must be at least 8 characters long."
  }
}

variable "manage_master_user_password" {
  description = "Whether to use AWS managed master password"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for Aurora cluster (uses default VPC if not specified)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for Aurora cluster (uses default subnets if not specified)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Aurora cluster"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Preferred backup window in UTC (format: hh24:mi-hh24:mi)"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.preferred_backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window (format: ddd:hh24:mi-ddd:hh24:mi)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# Aurora Serverless v2 Scaling Configuration
variable "serverless_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 0.5
  
  validation {
    condition = var.serverless_min_capacity >= 0.5 && var.serverless_min_capacity <= 128
    error_message = "Minimum capacity must be between 0.5 and 128 ACU."
  }
}

variable "serverless_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACU)"
  type        = number
  default     = 16
  
  validation {
    condition = var.serverless_max_capacity >= 0.5 && var.serverless_max_capacity <= 128
    error_message = "Maximum capacity must be between 0.5 and 128 ACU."
  }
}

variable "enable_performance_insights" {
  description = "Whether to enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 31, 93, 186, 372, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be one of: 7, 31, 93, 186, 372, 731."
  }
}

# Read Replica Configuration
variable "enable_read_replicas" {
  description = "Whether to create read replicas"
  type        = bool
  default     = true
}

variable "read_replica_count" {
  description = "Number of read replicas to create"
  type        = number
  default     = 2
  
  validation {
    condition = var.read_replica_count >= 0 && var.read_replica_count <= 15
    error_message = "Read replica count must be between 0 and 15."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime for scaling functions"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Cost Monitoring Configuration
variable "enable_cost_monitoring" {
  description = "Whether to enable cost monitoring and alerting"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit for Aurora costs in USD"
  type        = number
  default     = 200
  
  validation {
    condition = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

variable "cost_alert_email" {
  description = "Email address for cost alerts (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.cost_alert_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.cost_alert_email))
    error_message = "Cost alert email must be a valid email address."
  }
}

# EventBridge Scheduling Configuration
variable "cost_aware_scaling_schedule" {
  description = "EventBridge schedule expression for cost-aware scaling (rate or cron)"
  type        = string
  default     = "rate(15 minutes)"
}

variable "auto_pause_resume_schedule" {
  description = "EventBridge schedule expression for auto-pause/resume (rate or cron)"
  type        = string
  default     = "rate(1 hour)"
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}