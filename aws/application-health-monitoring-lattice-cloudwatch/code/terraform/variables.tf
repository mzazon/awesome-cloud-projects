# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "health-monitor"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID for VPC Lattice service network association"
  type        = string
  default     = null
}

variable "use_default_vpc" {
  description = "Whether to use the default VPC if vpc_id is not specified"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "List of subnet IDs for target group and service endpoints"
  type        = list(string)
  default     = []
}

# VPC Lattice Configuration
variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = ""
}

variable "service_name" {
  description = "Name for the VPC Lattice service"
  type        = string
  default     = ""
}

variable "target_group_name" {
  description = "Name for the VPC Lattice target group"
  type        = string
  default     = ""
}

variable "service_network_auth_type" {
  description = "Authentication type for the service network"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition = contains(["NONE", "AWS_IAM"], var.service_network_auth_type)
    error_message = "Service network auth type must be either 'NONE' or 'AWS_IAM'."
  }
}

variable "service_auth_type" {
  description = "Authentication type for the service"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition = contains(["NONE", "AWS_IAM"], var.service_auth_type)
    error_message = "Service auth type must be either 'NONE' or 'AWS_IAM'."
  }
}

# Health Check Configuration
variable "health_check_enabled" {
  description = "Whether to enable health checks for the target group"
  type        = bool
  default     = true
}

variable "health_check_interval_seconds" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.health_check_interval_seconds >= 5 && var.health_check_interval_seconds <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout_seconds" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition = var.health_check_timeout_seconds >= 1 && var.health_check_timeout_seconds <= 120
    error_message = "Health check timeout must be between 1 and 120 seconds."
  }
}

variable "healthy_threshold_count" {
  description = "Number of consecutive successful health checks required to mark target healthy"
  type        = number
  default     = 2
  
  validation {
    condition = var.healthy_threshold_count >= 2 && var.healthy_threshold_count <= 10
    error_message = "Healthy threshold count must be between 2 and 10."
  }
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive failed health checks required to mark target unhealthy"
  type        = number
  default     = 2
  
  validation {
    condition = var.unhealthy_threshold_count >= 2 && var.unhealthy_threshold_count <= 10
    error_message = "Unhealthy threshold count must be between 2 and 10."
  }
}

variable "health_check_path" {
  description = "Path for health check requests"
  type        = string
  default     = "/health"
}

variable "health_check_protocol" {
  description = "Protocol for health checks"
  type        = string
  default     = "HTTP"
  
  validation {
    condition = contains(["HTTP", "HTTPS"], var.health_check_protocol)
    error_message = "Health check protocol must be either 'HTTP' or 'HTTPS'."
  }
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 80
  
  validation {
    condition = var.health_check_port >= 1 && var.health_check_port <= 65535
    error_message = "Health check port must be between 1 and 65535."
  }
}

# CloudWatch Alarm Configuration
variable "high_5xx_threshold" {
  description = "Threshold for high 5XX error rate alarm"
  type        = number
  default     = 10
  
  validation {
    condition = var.high_5xx_threshold > 0
    error_message = "High 5XX threshold must be greater than 0."
  }
}

variable "request_timeout_threshold" {
  description = "Threshold for request timeout alarm"
  type        = number
  default     = 5
  
  validation {
    condition = var.request_timeout_threshold > 0
    error_message = "Request timeout threshold must be greater than 0."
  }
}

variable "high_response_time_threshold" {
  description = "Threshold for high response time alarm (in milliseconds)"
  type        = number
  default     = 2000
  
  validation {
    condition = var.high_response_time_threshold > 0
    error_message = "High response time threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for alarms"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 24
    error_message = "Alarm evaluation periods must be between 1 and 24."
  }
}

variable "alarm_period" {
  description = "Period for CloudWatch alarms in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, or 3600 seconds."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the remediation Lambda function"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# SNS Configuration
variable "sns_topic_name" {
  description = "Name for the SNS topic"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for health alert notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format or empty string."
  }
}

# CloudWatch Dashboard Configuration
variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = ""
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}