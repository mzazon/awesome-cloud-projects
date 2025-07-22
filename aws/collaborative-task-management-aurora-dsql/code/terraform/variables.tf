# Input variables for the real-time collaborative task management infrastructure
# These variables allow customization of the deployment for different environments

# Regional Configuration Variables
variable "aws_region" {
  description = "Primary AWS region for Aurora DSQL cluster and Lambda deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "eu-central-1", 
      "ap-southeast-1", "ap-northeast-1"
    ], var.aws_region)
    error_message = "Region must be one that supports Aurora PostgreSQL Global Database: us-east-1, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-northeast-1."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for multi-region Aurora DSQL setup"
  type        = string
  default     = "us-west-2"

  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "eu-central-1", 
      "ap-southeast-1", "ap-northeast-1"
    ], var.secondary_region)
    error_message = "Secondary region must support Aurora PostgreSQL Global Database and be different from primary region."
  }
}

# Environment and Naming Variables
variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "real-time-task-mgmt"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix for unique resource naming (leave empty for auto-generation)"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]*$", var.random_suffix))
    error_message = "Random suffix must contain only lowercase letters and numbers."
  }
}

# Aurora PostgreSQL Configuration
variable "dsql_cluster_name" {
  description = "Name for the Aurora PostgreSQL cluster (keeping variable name for backward compatibility)"
  type        = string
  default     = ""
}

variable "dsql_deletion_protection" {
  description = "Enable deletion protection for Aurora PostgreSQL cluster"
  type        = bool
  default     = false
}

# EventBridge Configuration
variable "event_bus_name" {
  description = "Name for the custom EventBridge event bus"
  type        = string
  default     = ""
}

variable "event_retention_days" {
  description = "Number of days to retain EventBridge events"
  type        = number
  default     = 7

  validation {
    condition     = var.event_retention_days >= 1 && var.event_retention_days <= 365
    error_message = "Event retention days must be between 1 and 365."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the task processor Lambda function"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  description = "Runtime environment for Lambda function"
  type        = string
  default     = "python3.12"

  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12", "python3.13"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
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

variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda function"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be either x86_64 or arm64."
  }
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_cloudwatch_insights" {
  description = "Enable CloudWatch Insights for log analysis"
  type        = bool
  default     = true
}

variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Database Configuration
variable "db_username" {
  description = "Username for Aurora PostgreSQL database connection"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "db_password" {
  description = "Password for Aurora PostgreSQL database connection (leave empty for auto-generation)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_database_encryption" {
  description = "Enable encryption at rest for Aurora PostgreSQL"
  type        = bool
  default     = true
}

# Security and Compliance Configuration
variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Aurora PostgreSQL"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the task management API"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Performance and Scaling Configuration
variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (-1 for unreserved)"
  type        = number
  default     = -1

  validation {
    condition     = var.lambda_reserved_concurrency == -1 || var.lambda_reserved_concurrency >= 1
    error_message = "Reserved concurrency must be -1 (unreserved) or a positive integer."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1 && var.cloudwatch_alarm_evaluation_periods <= 5
    error_message = "Evaluation periods must be between 1 and 5."
  }
}

# Cost Optimization Settings
variable "enable_cost_allocation_tags" {
  description = "Enable detailed cost allocation tags for billing analysis"
  type        = bool
  default     = true
}

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda function (0 to disable)"
  type        = number
  default     = 0

  validation {
    condition     = var.lambda_provisioned_concurrency >= 0
    error_message = "Provisioned concurrency must be a non-negative integer."
  }
}

# Feature Flags
variable "enable_multi_region_deployment" {
  description = "Deploy resources in multiple regions for high availability"
  type        = bool
  default     = true
}

variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue for failed Lambda invocations"
  type        = bool
  default     = true
}

variable "enable_event_replay" {
  description = "Enable EventBridge event replay functionality"
  type        = bool
  default     = false
}

# Integration Configuration
variable "external_event_sources" {
  description = "External event sources allowed to publish to EventBridge bus"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for source in var.external_event_sources : can(regex("^[a-zA-Z0-9.-]+$", source))
    ])
    error_message = "External event sources must contain only alphanumeric characters, dots, and hyphens."
  }
}

variable "notification_endpoints" {
  description = "SNS topic ARNs for task management notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.notification_endpoints : can(regex("^arn:aws:sns:", arn))
    ])
    error_message = "Notification endpoints must be valid SNS topic ARNs."
  }
}