# Variables for AWS Intelligent Document Processing with Amazon Textract
# These variables allow customization of the document processing pipeline
# for different environments and use cases

# Project and Environment Configuration
variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "textract-processor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) for resource organization"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# S3 Configuration
variable "documents_prefix" {
  description = "S3 prefix for storing incoming documents that trigger processing"
  type        = string
  default     = "documents"
  
  validation {
    condition     = can(regex("^[a-z0-9-/]*[a-z0-9-]$", var.documents_prefix))
    error_message = "Documents prefix must contain only lowercase letters, numbers, hyphens, and forward slashes."
  }
}

variable "results_prefix" {
  description = "S3 prefix for storing Textract processing results and metadata"
  type        = string
  default     = "results"
  
  validation {
    condition     = can(regex("^[a-z0-9-/]*[a-z0-9-]$", var.results_prefix))
    error_message = "Results prefix must contain only lowercase letters, numbers, hyphens, and forward slashes."
  }
}

# Lambda Function Configuration
variable "lambda_runtime" {
  description = "Python runtime version for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Maximum execution time for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Document Processing Configuration
variable "supported_formats" {
  description = "List of supported document formats for processing"
  type        = list(string)
  default     = ["pdf", "png", "jpg", "jpeg", "tiff", "txt"]
  
  validation {
    condition     = length(var.supported_formats) > 0
    error_message = "At least one supported format must be specified."
  }
}

variable "textract_api_version" {
  description = "Amazon Textract API version to use for document processing"
  type        = string
  default     = "2018-06-27"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.textract_api_version))
    error_message = "Textract API version must be in YYYY-MM-DD format."
  }
}

# Monitoring and Logging Configuration
variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for monitoring Lambda function performance"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "log_level" {
  description = "Logging level for Lambda function (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

# CloudWatch Alarms Configuration
variable "error_threshold" {
  description = "Number of Lambda function errors that trigger an alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_threshold > 0
    error_message = "Error threshold must be greater than 0."
  }
}

variable "duration_threshold" {
  description = "Lambda function duration in milliseconds that triggers an alarm"
  type        = number
  default     = 45000
  
  validation {
    condition     = var.duration_threshold > 0 && var.duration_threshold <= 900000
    error_message = "Duration threshold must be between 1 and 900000 milliseconds."
  }
}

variable "alarm_actions" {
  description = "List of ARNs to notify when CloudWatch alarms are triggered (e.g., SNS topics)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.alarm_actions : can(regex("^arn:aws:", arn))
    ])
    error_message = "All alarm actions must be valid AWS ARNs."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Additional tags to apply to all resources for organization and cost tracking"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags can be applied to resources."
  }
}

# Security Configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 bucket (requires additional KMS key configuration)"
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (only used if enable_kms_encryption is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_kms_encryption == false || (
      var.enable_kms_encryption == true && var.kms_key_id != ""
    )
    error_message = "KMS key ID must be provided when KMS encryption is enabled."
  }
}

# Advanced Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring features for performance insights"
  type        = bool
  default     = false
}

variable "max_concurrent_executions" {
  description = "Maximum number of concurrent Lambda function executions (0 for no limit)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.max_concurrent_executions >= 0
    error_message = "Maximum concurrent executions must be 0 or greater."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda function performance analysis"
  type        = bool
  default     = false
}

# Network Configuration (for VPC deployment)
variable "vpc_id" {
  description = "VPC ID for Lambda function deployment (optional for VPC configuration)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for Lambda function deployment in VPC"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for Lambda function in VPC"
  type        = list(string)
  default     = []
}

# Cost Optimization
variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for automatic cost optimization"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Number of days after which objects transition to Infrequent Access storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days after which objects transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 30
    error_message = "Transition to Glacier must be at least 30 days."
  }
}