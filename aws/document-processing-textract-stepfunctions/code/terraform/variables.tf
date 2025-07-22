# Input Variables for Document Processing Pipeline
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "textract-pipeline"
  
  validation {
    condition = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

variable "results_processor_timeout" {
  description = "Results processor Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.results_processor_timeout >= 3 && var.results_processor_timeout <= 900
    error_message = "Results processor timeout must be between 3 and 900 seconds."
  }
}

variable "results_processor_memory_size" {
  description = "Results processor Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.results_processor_memory_size >= 128 && var.results_processor_memory_size <= 10240
    error_message = "Results processor memory size must be between 128 and 10240 MB."
  }
}

variable "notification_email" {
  description = "Email address for failure notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "allowed_file_types" {
  description = "List of allowed file extensions for document processing"
  type        = list(string)
  default     = ["pdf", "png", "jpg", "jpeg", "tiff"]
  
  validation {
    condition = length(var.allowed_file_types) > 0
    error_message = "At least one file type must be specified."
  }
}

variable "textract_features" {
  description = "Textract features to enable during document analysis"
  type        = list(string)
  default     = ["TABLES", "FORMS", "SIGNATURES"]
  
  validation {
    condition = length(setintersection(var.textract_features, ["TABLES", "FORMS", "SIGNATURES", "LAYOUT", "QUERIES"])) == length(var.textract_features)
    error_message = "Textract features must be from: TABLES, FORMS, SIGNATURES, LAYOUT, QUERIES."
  }
}

variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "step_function_logging_level" {
  description = "Step Functions logging level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_function_logging_level)
    error_message = "Step Functions logging level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "enable_cost_allocation_tags" {
  description = "Enable additional cost allocation tags"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain archived documents"
  type        = number
  default     = 90
  
  validation {
    condition = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}