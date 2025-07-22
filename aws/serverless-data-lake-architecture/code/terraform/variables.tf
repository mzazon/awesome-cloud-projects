# Core configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project (used as prefix for resource names)"
  type        = string
  default     = "advanced-serverless-datalake"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-32 characters, start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "glue_crawler_schedule" {
  description = "Glue crawler schedule expression"
  type        = string
  default     = "cron(0 */6 * * ? *)"
  
  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.glue_crawler_schedule))
    error_message = "Glue crawler schedule must be a valid cron expression."
  }
}

variable "s3_force_destroy" {
  description = "Whether to force destroy S3 buckets (true for dev environments)"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs_retention" {
  description = "Enable CloudWatch logs retention policy"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch logs retention must be a valid retention period in days."
  }
}

variable "lambda_layer_description" {
  description = "Description for the Lambda layer"
  type        = string
  default     = "Shared utilities and dependencies for data lake processing"
}

variable "eventbridge_rule_state" {
  description = "State of EventBridge rules (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.eventbridge_rule_state)
    error_message = "EventBridge rule state must be either ENABLED or DISABLED."
  }
}

variable "glue_job_max_concurrent_runs" {
  description = "Maximum number of concurrent runs for Glue jobs"
  type        = number
  default     = 1
  
  validation {
    condition     = var.glue_job_max_concurrent_runs >= 1 && var.glue_job_max_concurrent_runs <= 1000
    error_message = "Glue job max concurrent runs must be between 1 and 1000."
  }
}