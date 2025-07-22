# Input variables for medical image processing infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the medical imaging project"
  type        = string
  default     = "medical-imaging"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "datastore_name" {
  description = "Name for the AWS HealthImaging data store"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_s3_lifecycle" {
  description = "Enable lifecycle policies on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_transition_days" {
  description = "Number of days before transitioning objects to IA storage class"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_transition_days >= 1 && var.s3_transition_days <= 365
    error_message = "S3 transition days must be between 1 and 365."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "step_functions_type" {
  description = "Type of Step Functions state machine (STANDARD or EXPRESS)"
  type        = string
  default     = "EXPRESS"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.step_functions_type)
    error_message = "Step Functions type must be either STANDARD or EXPRESS."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# HIPAA Compliance and Security Variables
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for all applicable resources"
  type        = bool
  default     = true
}

variable "kms_deletion_window" {
  description = "Number of days before KMS key deletion (7-30)"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for VPC endpoints (required if enable_vpc_endpoints is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC endpoints (required if enable_vpc_endpoints is true)"
  type        = list(string)
  default     = []
}