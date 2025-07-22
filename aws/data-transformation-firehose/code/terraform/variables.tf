variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "real-time-data-transformation"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = null
  
  validation {
    condition     = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Email address must be in valid format."
  }
}

variable "firehose_buffer_size" {
  description = "Buffer size in MB for Kinesis Firehose delivery (1-5)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 5
    error_message = "Firehose buffer size must be between 1 and 5 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Buffer interval in seconds for Kinesis Firehose delivery (60-900)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

variable "lambda_buffer_size" {
  description = "Buffer size in MB for Lambda processing (1-3)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.lambda_buffer_size >= 1 && var.lambda_buffer_size <= 3
    error_message = "Lambda buffer size must be between 1 and 3 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (30-900)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB (128-10240)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "min_log_level" {
  description = "Minimum log level to process (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.min_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "fields_to_redact" {
  description = "List of fields to redact from logs for privacy/compliance"
  type        = list(string)
  default     = ["password", "creditCard", "ssn", "token", "secret"]
  
  validation {
    condition     = alltrue([for field in var.fields_to_redact : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", field))])
    error_message = "Field names must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "data_freshness_threshold" {
  description = "Data freshness threshold in seconds for CloudWatch alarm"
  type        = number
  default     = 900
  
  validation {
    condition     = var.data_freshness_threshold >= 300 && var.data_freshness_threshold <= 3600
    error_message = "Data freshness threshold must be between 300 and 3600 seconds."
  }
}

variable "s3_compression_format" {
  description = "Compression format for S3 objects (GZIP, SNAPPY, ZIP, UNCOMPRESSED)"
  type        = string
  default     = "GZIP"
  
  validation {
    condition     = contains(["GZIP", "SNAPPY", "ZIP", "UNCOMPRESSED"], var.s3_compression_format)
    error_message = "S3 compression format must be one of: GZIP, SNAPPY, ZIP, UNCOMPRESSED."
  }
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Kinesis Firehose"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}