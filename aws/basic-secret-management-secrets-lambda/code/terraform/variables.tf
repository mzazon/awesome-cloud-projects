# variables.tf
# Variable definitions for AWS basic secret management with Secrets Manager and Lambda

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "secret-demo"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod, etc.)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = null # Will be generated based on project_name and environment if not provided
}

variable "secret_name" {
  description = "Name for the Secrets Manager secret"
  type        = string
  default     = null # Will be generated based on project_name and environment if not provided
}

variable "secret_description" {
  description = "Description for the Secrets Manager secret"
  type        = string
  default     = "Sample application secrets for Lambda demo"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.11", "python3.10", "python3.9", "python3.8"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "secret_recovery_window" {
  description = "Number of days AWS Secrets Manager waits before permanent deletion (0 for immediate deletion, 7-30 for recovery window)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.secret_recovery_window == 0 || (var.secret_recovery_window >= 7 && var.secret_recovery_window <= 30)
    error_message = "Recovery window must be 0 (immediate deletion) or between 7 and 30 days."
  }
}

variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = false
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations (only used if enable_secret_rotation is true)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "Rotation days must be between 1 and 365."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting the secret (leave null to use default AWS managed key)"
  type        = string
  default     = null
}

variable "lambda_extensions_layer_version" {
  description = "Version of the AWS Parameters and Secrets Lambda Extension layer"
  type        = number
  default     = 18 # Latest version as of 2024
}

variable "extension_cache_enabled" {
  description = "Enable caching in the AWS Parameters and Secrets Lambda Extension"
  type        = bool
  default     = true
}

variable "extension_cache_size" {
  description = "Cache size for the AWS Parameters and Secrets Lambda Extension"
  type        = number
  default     = 1000
}

variable "extension_max_connections" {
  description = "Maximum connections for the AWS Parameters and Secrets Lambda Extension"
  type        = number
  default     = 3
}

variable "extension_http_port" {
  description = "HTTP port for the AWS Parameters and Secrets Lambda Extension"
  type        = number
  default     = 2773
}

variable "sample_secret_values" {
  description = "Sample secret values to store in Secrets Manager (for demo purposes)"
  type = object({
    database_host = string
    database_port = string
    database_name = string
    username      = string
    password      = string
  })
  default = {
    database_host = "mydb.cluster-xyz.us-east-1.rds.amazonaws.com"
    database_port = "5432"
    database_name = "production"
    username      = "appuser"
    password      = "secure-random-password-123"
  }
  sensitive = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Local values for computed names and common tags
locals {
  # Generate unique suffix for resources
  resource_suffix = random_string.suffix.result
  
  # Computed resource names
  lambda_function_name = coalesce(
    var.lambda_function_name,
    "${var.project_name}-${var.environment}-${local.resource_suffix}"
  )
  
  secret_name = coalesce(
    var.secret_name,
    "${var.project_name}-secrets-${var.environment}-${local.resource_suffix}"
  )
  
  iam_role_name = "${var.project_name}-lambda-role-${var.environment}-${local.resource_suffix}"
  
  # Lambda Extensions Layer ARN for current region
  extensions_layer_arn = "arn:aws:lambda:${data.aws_region.current.name}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:${var.lambda_extensions_layer_version}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "basic-secret-management-secrets-lambda"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Generate a random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}