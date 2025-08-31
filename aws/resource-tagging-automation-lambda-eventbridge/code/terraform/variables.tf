# variables.tf
# Variable definitions for AWS resource tagging automation infrastructure

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "resource-tagging-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
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

variable "cost_center" {
  description = "Cost center for billing and cost allocation"
  type        = string
  default     = "engineering"
}

variable "department" {
  description = "Department responsible for the resources"
  type        = string
  default     = "infrastructure"
}

variable "contact_email" {
  description = "Contact email for resource ownership and notifications"
  type        = string
  default     = "infrastructure@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.contact_email))
    error_message = "Contact email must be a valid email address."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for Lambda function"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 
      731, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}

variable "cloudtrail_events" {
  description = "List of CloudTrail events to monitor for resource tagging"
  type        = list(string)
  default = [
    "RunInstances",
    "CreateBucket", 
    "CreateDBInstance",
    "CreateFunction20150331"
  ]
}

variable "aws_services" {
  description = "List of AWS services to monitor for resource creation"
  type        = list(string)
  default = [
    "aws.ec2",
    "aws.s3", 
    "aws.rds",
    "aws.lambda"
  ]
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources created by automation"
  type        = map(string)
  default = {
    AutoTagged  = "true"
    ManagedBy   = "automation"
  }
}

variable "resource_name_suffix" {
  description = "Optional suffix for resource names (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_resource_group" {
  description = "Whether to create a Resource Group for tagged resources"
  type        = bool
  default     = true
}

variable "eventbridge_rule_description" {
  description = "Description for the EventBridge rule"
  type        = string
  default     = "Trigger Lambda function for automated resource tagging"
}