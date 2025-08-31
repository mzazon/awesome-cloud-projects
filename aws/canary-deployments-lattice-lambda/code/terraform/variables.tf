# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "canary-demo"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "canary-deployment-demo"
    Environment = "dev"
    Terraform   = "true"
    Recipe      = "canary-deployments-lattice-lambda"
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# VPC Lattice Configuration
variable "service_auth_type" {
  description = "VPC Lattice service authentication type"
  type        = string
  default     = "NONE"
  
  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.service_auth_type)
    error_message = "Service auth type must be NONE or AWS_IAM."
  }
}

variable "listener_protocol" {
  description = "VPC Lattice listener protocol"
  type        = string
  default     = "HTTP"
  
  validation {
    condition     = contains(["HTTP", "HTTPS"], var.listener_protocol)
    error_message = "Listener protocol must be HTTP or HTTPS."
  }
}

variable "listener_port" {
  description = "VPC Lattice listener port"
  type        = number
  default     = 80
  
  validation {
    condition     = var.listener_port >= 1 && var.listener_port <= 65535
    error_message = "Listener port must be between 1 and 65535."
  }
}

# Canary Deployment Configuration
variable "initial_canary_weight" {
  description = "Initial traffic weight for canary deployment (0-100)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.initial_canary_weight >= 0 && var.initial_canary_weight <= 100
    error_message = "Canary weight must be between 0 and 100."
  }
}

variable "production_weight" {
  description = "Initial traffic weight for production deployment (0-100)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.production_weight >= 0 && var.production_weight <= 100
    error_message = "Production weight must be between 0 and 100."
  }
}

# CloudWatch Monitoring Configuration
variable "error_threshold" {
  description = "Error count threshold for CloudWatch alarms"
  type        = number
  default     = 5
}

variable "duration_threshold" {
  description = "Duration threshold in milliseconds for CloudWatch alarms"
  type        = number
  default     = 5000
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
}

# Feature Flags
variable "enable_rollback_function" {
  description = "Enable automatic rollback Lambda function"
  type        = bool
  default     = true
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for rollback events"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}