# Core Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "data-quality-pipeline"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
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

# Data Configuration
variable "sample_data_enabled" {
  description = "Whether to create sample data for testing"
  type        = bool
  default     = true
}

variable "sample_data_content" {
  description = "Content of the sample CSV data for testing"
  type        = string
  default     = <<-EOT
customer_id,name,email,age,registration_date,purchase_amount
1,John Doe,john.doe@email.com,35,2024-01-15,299.99
2,Jane Smith,jane.smith@email.com,28,2024-02-20,159.50
3,Bob Johnson,,42,2024-01-30,899.00
4,Alice Brown,alice.brown@email.com,-5,2024-03-10,49.99
5,Charlie Wilson,invalid-email,30,2024-02-15,
6,Diana Davis,diana.davis@email.com,25,2024-01-05,199.75
EOT
}

# DataBrew Configuration
variable "databrew_job_max_capacity" {
  description = "Maximum capacity for DataBrew profile job"
  type        = number
  default     = 5
  
  validation {
    condition     = var.databrew_job_max_capacity >= 1 && var.databrew_job_max_capacity <= 100
    error_message = "DataBrew job max capacity must be between 1 and 100."
  }
}

variable "databrew_job_timeout" {
  description = "Timeout for DataBrew profile job in minutes"
  type        = number
  default     = 120
  
  validation {
    condition     = var.databrew_job_timeout >= 1 && var.databrew_job_timeout <= 2880
    error_message = "DataBrew job timeout must be between 1 and 2880 minutes."
  }
}

# Data Quality Rules Configuration
variable "email_validation_threshold" {
  description = "Threshold percentage for email format validation"
  type        = number
  default     = 90.0
  
  validation {
    condition     = var.email_validation_threshold >= 0 && var.email_validation_threshold <= 100
    error_message = "Email validation threshold must be between 0 and 100."
  }
}

variable "age_validation_threshold" {
  description = "Threshold percentage for age range validation"
  type        = number
  default     = 95.0
  
  validation {
    condition     = var.age_validation_threshold >= 0 && var.age_validation_threshold <= 100
    error_message = "Age validation threshold must be between 0 and 100."
  }
}

variable "purchase_amount_threshold" {
  description = "Threshold percentage for purchase amount completeness"
  type        = number
  default     = 90.0
  
  validation {
    condition     = var.purchase_amount_threshold >= 0 && var.purchase_amount_threshold <= 100
    error_message = "Purchase amount threshold must be between 0 and 100."
  }
}

variable "age_min_value" {
  description = "Minimum valid age value"
  type        = number
  default     = 0
}

variable "age_max_value" {
  description = "Maximum valid age value"
  type        = number
  default     = 120
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for data quality notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# S3 Configuration
variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket with objects (use with caution)"
  type        = bool
  default     = false
}

# Default Tags
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DataQualityPipeline"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Purpose     = "DataQuality"
  }
}