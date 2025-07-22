# Core project variables
variable "project_name" {
  description = "Name of the cost management tagging project"
  type        = string
  default     = "cost-mgmt-tagging"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment for the tagging strategy implementation"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region for deploying the tagging infrastructure"
  type        = string
  default     = "us-east-1"
}

# Tagging taxonomy variables
variable "default_cost_center" {
  description = "Default cost center for unassigned resources"
  type        = string
  default     = "Engineering"
  
  validation {
    condition     = contains(["Engineering", "Marketing", "Sales", "Finance", "Operations"], var.default_cost_center)
    error_message = "Cost center must be one of: Engineering, Marketing, Sales, Finance, Operations."
  }
}

variable "owner_email" {
  description = "Email address of the resource owner"
  type        = string
  default     = "devops@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Owner email must be a valid email address."
  }
}

variable "allowed_cost_centers" {
  description = "List of allowed cost centers for tag validation"
  type        = list(string)
  default     = ["Engineering", "Marketing", "Sales", "Finance", "Operations"]
}

variable "allowed_environments" {
  description = "List of allowed environments for tag validation"
  type        = list(string)
  default     = ["Production", "Staging", "Development", "Testing"]
}

variable "allowed_applications" {
  description = "List of allowed application types for tag validation"
  type        = list(string)
  default     = ["web", "api", "database", "cache", "queue"]
}

# SNS notification variables
variable "notification_email" {
  description = "Email address for tag compliance notifications"
  type        = string
  default     = "compliance@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

# AWS Config variables
variable "enable_config_recorder" {
  description = "Enable AWS Config configuration recorder"
  type        = bool
  default     = true
}

variable "include_global_resource_types" {
  description = "Include global resource types in Config recording"
  type        = bool
  default     = true
}

variable "config_delivery_frequency" {
  description = "Frequency for AWS Config delivery channel"
  type        = string
  default     = "TwentyFour_Hours"
  
  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", 
      "Twelve_Hours", "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Config delivery frequency must be a valid AWS Config delivery frequency."
  }
}

# Lambda function variables
variable "lambda_timeout" {
  description = "Timeout for the tag remediation Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the tag remediation Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Demo resources variables
variable "create_demo_resources" {
  description = "Create demo resources to test the tagging strategy"
  type        = bool
  default     = true
}

variable "demo_instance_type" {
  description = "EC2 instance type for demo resource"
  type        = string
  default     = "t2.micro"
}

# Cost allocation tags
variable "cost_allocation_tags" {
  description = "List of tags to use for cost allocation in AWS Cost Explorer"
  type        = list(string)
  default     = ["CostCenter", "Environment", "Project", "Owner", "Application"]
}

# Resource naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "tag-strategy"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only alphanumeric characters and hyphens."
  }
}