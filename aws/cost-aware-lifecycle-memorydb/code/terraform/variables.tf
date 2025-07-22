# Input Variables for Cost-Aware MemoryDB Lifecycle Management
# This file defines all configurable parameters for the infrastructure deployment

# AWS Region Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in format like 'us-east-1' or 'eu-west-1'."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for resource allocation and billing"
  type        = string
  default     = "engineering"
}

# MemoryDB Cluster Configuration
variable "memorydb_node_type" {
  description = "Initial MemoryDB node type for cost-aware scaling"
  type        = string
  default     = "db.t4g.small"

  validation {
    condition = can(regex("^db\\.(t4g|r6g|r7g)\\.(nano|micro|small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge)$", var.memorydb_node_type))
    error_message = "MemoryDB node type must be a valid instance type like 'db.t4g.small' or 'db.r6g.large'."
  }
}

variable "memorydb_num_shards" {
  description = "Number of shards for MemoryDB cluster"
  type        = number
  default     = 1

  validation {
    condition     = var.memorydb_num_shards >= 1 && var.memorydb_num_shards <= 500
    error_message = "Number of shards must be between 1 and 500."
  }
}

variable "memorydb_num_replicas_per_shard" {
  description = "Number of replicas per shard for high availability"
  type        = number
  default     = 0

  validation {
    condition     = var.memorydb_num_replicas_per_shard >= 0 && var.memorydb_num_replicas_per_shard <= 5
    error_message = "Number of replicas per shard must be between 0 and 5."
  }
}

variable "memorydb_maintenance_window" {
  description = "Preferred maintenance window for MemoryDB cluster (UTC)"
  type        = string
  default     = "sun:03:00-sun:04:00"

  validation {
    condition = can(regex("^(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]-(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]$", var.memorydb_maintenance_window))
    error_message = "Maintenance window must be in format 'ddd:hh:mm-ddd:hh:mm' like 'sun:03:00-sun:04:00'."
  }
}

# Lambda Function Configuration
variable "lambda_runtime" {
  description = "Runtime environment for Lambda function"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function (MB)"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function execution (seconds)"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_log_level" {
  description = "Logging level for Lambda function"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.lambda_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# EventBridge Scheduler Configuration
variable "business_hours_start_cron" {
  description = "Cron expression for business hours start (scale up)"
  type        = string
  default     = "0 8 ? * MON-FRI *"

  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/?]+ [0-9*,-/?]+ [0-9*,-/A-Z]+ [0-9*,-/A-Z]*$", var.business_hours_start_cron))
    error_message = "Cron expression must be valid EventBridge Scheduler format."
  }
}

variable "business_hours_end_cron" {
  description = "Cron expression for business hours end (scale down)"
  type        = string
  default     = "0 18 ? * MON-FRI *"

  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/?]+ [0-9*,-/?]+ [0-9*,-/A-Z]+ [0-9*,-/A-Z]*$", var.business_hours_end_cron))
    error_message = "Cron expression must be valid EventBridge Scheduler format."
  }
}

variable "weekly_analysis_cron" {
  description = "Cron expression for weekly cost analysis"
  type        = string
  default     = "0 9 ? * MON *"

  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/?]+ [0-9*,-/?]+ [0-9*,-/A-Z]+ [0-9*,-/A-Z]*$", var.weekly_analysis_cron))
    error_message = "Cron expression must be valid EventBridge Scheduler format."
  }
}

# Cost Management Configuration
variable "monthly_budget_limit" {
  description = "Monthly budget limit for MemoryDB costs (USD)"
  type        = number
  default     = 200

  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Budget limit must be greater than 0."
  }
}

variable "budget_alert_threshold_actual" {
  description = "Budget alert threshold for actual costs (percentage)"
  type        = number
  default     = 80

  validation {
    condition     = var.budget_alert_threshold_actual > 0 && var.budget_alert_threshold_actual <= 100
    error_message = "Budget alert threshold must be between 1 and 100 percent."
  }
}

variable "budget_alert_threshold_forecasted" {
  description = "Budget alert threshold for forecasted costs (percentage)"
  type        = number
  default     = 90

  validation {
    condition     = var.budget_alert_threshold_forecasted > 0 && var.budget_alert_threshold_forecasted <= 100
    error_message = "Budget alert threshold must be between 1 and 100 percent."
  }
}

variable "cost_alert_email" {
  description = "Email address for cost alerts and budget notifications"
  type        = string
  default     = "admin@example.com"

  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.cost_alert_email))
    error_message = "Must be a valid email address."
  }
}

# Cost Optimization Thresholds
variable "scale_up_cost_threshold" {
  description = "Cost threshold for scale up decisions (USD)"
  type        = number
  default     = 100

  validation {
    condition     = var.scale_up_cost_threshold > 0
    error_message = "Scale up cost threshold must be greater than 0."
  }
}

variable "scale_down_cost_threshold" {
  description = "Cost threshold for scale down decisions (USD)"
  type        = number
  default     = 50

  validation {
    condition     = var.scale_down_cost_threshold > 0
    error_message = "Scale down cost threshold must be greater than 0."
  }
}

variable "weekly_analysis_cost_threshold" {
  description = "Cost threshold for weekly analysis triggers (USD)"
  type        = number
  default     = 150

  validation {
    condition     = var.weekly_analysis_cost_threshold > 0
    error_message = "Weekly analysis cost threshold must be greater than 0."
  }
}

# CloudWatch Monitoring Configuration
variable "weekly_cost_alarm_threshold" {
  description = "CloudWatch alarm threshold for weekly MemoryDB costs (USD)"
  type        = number
  default     = 150

  validation {
    condition     = var.weekly_cost_alarm_threshold > 0
    error_message = "Weekly cost alarm threshold must be greater than 0."
  }
}

variable "lambda_error_alarm_threshold" {
  description = "Lambda error count threshold for CloudWatch alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.lambda_error_alarm_threshold > 0
    error_message = "Lambda error alarm threshold must be greater than 0."
  }
}

# VPC and Networking Configuration
variable "use_default_vpc" {
  description = "Whether to use the default VPC for MemoryDB cluster"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for MemoryDB cluster (if not using default VPC)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for MemoryDB cluster (if not using default VPC)"
  type        = list(string)
  default     = []
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access MemoryDB cluster"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cost-aware-memorydb"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

# Feature Flags
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for enhanced visibility"
  type        = bool
  default     = true
}

variable "enable_cost_budget" {
  description = "Enable AWS Budgets for cost monitoring"
  type        = bool
  default     = true
}

variable "enable_scheduler_automation" {
  description = "Enable EventBridge Scheduler automation for cost optimization"
  type        = bool
  default     = true
}