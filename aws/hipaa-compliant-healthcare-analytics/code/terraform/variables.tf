# Healthcare Data Processing Pipelines Variables
# This file defines all configurable variables for the HealthLake infrastructure

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "healthcare"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_preload_data" {
  description = "Whether to preload synthetic healthcare data for testing"
  type        = bool
  default     = true
}

variable "fhir_version" {
  description = "FHIR version for the HealthLake data store"
  type        = string
  default     = "R4"
  
  validation {
    condition     = contains(["R4"], var.fhir_version)
    error_message = "FHIR version must be R4 (currently the only supported version)."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "Encryption algorithm for S3 buckets"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for Lambda functions"
  type        = bool
  default     = false
}

variable "event_rule_state" {
  description = "State of EventBridge rules (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.event_rule_state)
    error_message = "Event rule state must be either ENABLED or DISABLED."
  }
}

variable "enable_vpc_configuration" {
  description = "Enable VPC configuration for Lambda functions"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnet IDs for Lambda functions (required if enable_vpc_configuration is true)"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs for Lambda functions (required if enable_vpc_configuration is true)"
  type        = list(string)
  default     = []
}

variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue for Lambda functions"
  type        = bool
  default     = false
}

variable "reserved_concurrent_executions" {
  description = "Number of reserved concurrent executions for Lambda functions (-1 for unrestricted)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.reserved_concurrent_executions >= -1
    error_message = "Reserved concurrent executions must be -1 (unrestricted) or a positive number."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (optional, used when s3_encryption_algorithm is aws:kms)"
  type        = string
  default     = null
}

variable "notification_email" {
  description = "Email address for notifications about HealthLake operations"
  type        = string
  default     = null
  
  validation {
    condition     = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_backup" {
  description = "Enable automatic backup for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 1 and 35."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Cannot specify more than 50 tags."
  }
}

variable "cost_center" {
  description = "Cost center for billing attribution"
  type        = string
  default     = null
}

variable "compliance_level" {
  description = "Compliance level requirement (HIPAA, SOC2, etc.)"
  type        = string
  default     = "HIPAA"
  
  validation {
    condition     = contains(["HIPAA", "SOC2", "PCI", "GDPR", "None"], var.compliance_level)
    error_message = "Compliance level must be one of: HIPAA, SOC2, PCI, GDPR, None."
  }
}

variable "data_classification" {
  description = "Data classification level for healthcare data"
  type        = string
  default     = "PHI"
  
  validation {
    condition     = contains(["PHI", "PII", "Confidential", "Internal", "Public"], var.data_classification)
    error_message = "Data classification must be one of: PHI, PII, Confidential, Internal, Public."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for HealthLake API calls"
  type        = bool
  default     = true
}

variable "enable_config_rules" {
  description = "Enable AWS Config rules for compliance monitoring"
  type        = bool
  default     = false
}

variable "performance_mode" {
  description = "Performance mode for the solution (cost-optimized or performance-optimized)"
  type        = string
  default     = "cost-optimized"
  
  validation {
    condition     = contains(["cost-optimized", "performance-optimized"], var.performance_mode)
    error_message = "Performance mode must be either cost-optimized or performance-optimized."
  }
}