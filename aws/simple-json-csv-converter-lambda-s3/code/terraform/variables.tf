# =============================================================================
# VARIABLES - JSON to CSV Converter with Lambda and S3
# =============================================================================
# This file defines all the configurable variables for the JSON-to-CSV
# converter infrastructure. These variables allow customization of resource
# names, configurations, and optional features while maintaining secure
# defaults and following AWS best practices.
# =============================================================================

# =============================================================================
# NAMING AND IDENTIFICATION
# =============================================================================

variable "input_bucket_prefix" {
  description = "Prefix for the input S3 bucket name (will be suffixed with random hex)"
  type        = string
  default     = "json-input"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,50}$", var.input_bucket_prefix))
    error_message = "Input bucket prefix must be 3-50 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "output_bucket_prefix" {
  description = "Prefix for the output S3 bucket name (will be suffixed with random hex)"
  type        = string
  default     = "csv-output"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,50}$", var.output_bucket_prefix))
    error_message = "Output bucket prefix must be 3-50 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "lambda_function_name" {
  description = "Base name for the Lambda function (will be suffixed with random hex)"
  type        = string
  default     = "json-csv-converter"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.lambda_function_name))
    error_message = "Lambda function name must be 1-50 characters, letters, numbers, hyphens, and underscores only."
  }
}

variable "input_file_prefix" {
  description = "Prefix filter for input files (empty string for no prefix filter)"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.input_file_prefix) <= 100
    error_message = "Input file prefix must be 100 characters or less."
  }
}

# =============================================================================
# LAMBDA FUNCTION CONFIGURATION
# =============================================================================

variable "lambda_runtime" {
  description = "Runtime environment for the Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# =============================================================================
# LOGGING AND MONITORING
# =============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for monitoring Lambda function performance"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications (leave empty to disable notifications)"
  type        = string
  default     = ""
  
  validation {
    condition = var.alarm_sns_topic_arn == "" || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9-_]+$", var.alarm_sns_topic_arn))
    error_message = "SNS topic ARN must be empty or a valid SNS topic ARN."
  }
}

# =============================================================================
# TAGGING
# =============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "JSON-CSV-Converter"
    Environment = "development"
    ManagedBy   = "terraform"
    Purpose     = "data-transformation"
    Category    = "serverless"
  }
  
  validation {
    condition     = length(var.common_tags) <= 50
    error_message = "Maximum of 50 tags are allowed."
  }
}

# =============================================================================
# OPTIONAL FEATURES
# =============================================================================

variable "enable_s3_encryption" {
  description = "Enable server-side encryption for S3 buckets (always enabled for security)"
  type        = bool
  default     = true
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 buckets (recommended for data protection)"
  type        = bool
  default     = true
}

variable "enable_public_access_block" {
  description = "Block public access to S3 buckets (always enabled for security)"
  type        = bool
  default     = true
}

# =============================================================================
# ENVIRONMENT-SPECIFIC CONFIGURATIONS
# =============================================================================

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "cost_center" {
  description = "Cost center for billing and resource allocation"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.cost_center) <= 50
    error_message = "Cost center must be 50 characters or less."
  }
}

variable "owner_email" {
  description = "Email address of the resource owner for contact purposes"
  type        = string
  default     = ""
  
  validation {
    condition = var.owner_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.owner_email))
    error_message = "Owner email must be empty or a valid email address."
  }
}

# =============================================================================
# REGIONAL CONFIGURATION
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment (defaults to provider region)"
  type        = string
  default     = ""
  
  validation {
    condition = var.aws_region == "" || can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be empty or a valid AWS region format (e.g., us-east-1)."
  }
}

# =============================================================================
# SECURITY CONFIGURATIONS
# =============================================================================

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for the Lambda function (0 = unreserved, -1 = disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lambda_reserved_concurrency >= -1 && var.lambda_reserved_concurrency <= 1000
    error_message = "Lambda reserved concurrency must be between -1 and 1000."
  }
}

variable "enable_lambda_insights" {
  description = "Enable AWS Lambda Insights for enhanced monitoring"
  type        = bool
  default     = false
}

variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda function"
  type        = string
  default     = "x86_64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be x86_64 or arm64."
  }
}

# =============================================================================
# PERFORMANCE TUNING
# =============================================================================

variable "max_concurrent_executions" {
  description = "Maximum number of concurrent Lambda executions (helps control costs)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_concurrent_executions >= 1 && var.max_concurrent_executions <= 1000
    error_message = "Maximum concurrent executions must be between 1 and 1000."
  }
}

variable "lambda_dead_letter_config" {
  description = "Dead letter queue configuration for failed executions"
  type = object({
    target_arn = string
  })
  default = null
}

# =============================================================================
# DATA PROCESSING CONFIGURATION
# =============================================================================

variable "supported_file_extensions" {
  description = "List of supported file extensions for processing"
  type        = list(string)
  default     = [".json"]
  
  validation {
    condition     = length(var.supported_file_extensions) > 0
    error_message = "At least one file extension must be specified."
  }
}

variable "max_file_size_mb" {
  description = "Maximum file size in MB that can be processed"
  type        = number
  default     = 50
  
  validation {
    condition     = var.max_file_size_mb > 0 && var.max_file_size_mb <= 256
    error_message = "Maximum file size must be between 1 and 256 MB."
  }
}