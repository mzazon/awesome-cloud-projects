# Input variables for the network troubleshooting solution

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "network-troubleshooting"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
  
  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "instance_type" {
  description = "EC2 instance type for test instances"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "alarm_error_threshold" {
  description = "Threshold for 5XX error count alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.alarm_error_threshold > 0
    error_message = "Error threshold must be greater than 0."
  }
}

variable "alarm_latency_threshold_ms" {
  description = "Threshold for response time alarm in milliseconds"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.alarm_latency_threshold_ms > 0
    error_message = "Latency threshold must be greater than 0."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}