# ==============================================================================
# ZERO TRUST SECURITY ARCHITECTURE - TERRAFORM VARIABLES
# ==============================================================================

# General Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "zero-trust"
  
  validation {
    condition     = length(var.prefix) <= 10 && can(regex("^[a-z0-9-]+$", var.prefix))
    error_message = "Prefix must be 10 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

variable "trusted_ip_ranges" {
  description = "Trusted IP ranges for zero trust network access"
  type        = list(string)
  default     = ["203.0.113.0/24", "198.51.100.0/24"]
  
  validation {
    condition = alltrue([
      for cidr in var.trusted_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All trusted IP ranges must be valid IPv4 CIDR blocks."
  }
}

# Security Configuration
variable "enable_guardduty" {
  description = "Enable Amazon GuardDuty for threat detection"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub for security posture management"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config for compliance monitoring"
  type        = bool
  default     = true
}

variable "enable_inspector" {
  description = "Enable Amazon Inspector for vulnerability assessments"
  type        = bool
  default     = true
}

variable "guardduty_finding_frequency" {
  description = "Frequency of GuardDuty findings publication"
  type        = string
  default     = "FIFTEEN_MINUTES"
  
  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "GuardDuty finding frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

variable "config_delivery_frequency" {
  description = "Frequency of AWS Config configuration snapshots"
  type        = string
  default     = "TwentyFour_Hours"
  
  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Config delivery frequency must be a valid AWS Config frequency value."
  }
}

# IAM Identity Center Configuration
variable "identity_center_instance_arn" {
  description = "ARN of existing IAM Identity Center instance (leave empty to create new)"
  type        = string
  default     = ""
}

variable "session_duration" {
  description = "Maximum session duration for Identity Center permission sets (in ISO 8601 format)"
  type        = string
  default     = "PT8H"
  
  validation {
    condition     = can(regex("^PT([0-9]+H)?([0-9]+M)?$", var.session_duration))
    error_message = "Session duration must be in ISO 8601 format (e.g., PT8H for 8 hours)."
  }
}

# Monitoring Configuration
variable "cloudwatch_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid AWS CloudWatch retention value."
  }
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for security alerts"
  type        = string
  default     = "security-team@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

# KMS Configuration
variable "kms_key_deletion_window" {
  description = "Number of days before KMS key deletion (7-30 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# S3 Configuration
variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 buckets with objects (use with caution)"
  type        = bool
  default     = false
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_mfa_delete" {
  description = "Enable MFA delete for S3 buckets (requires manual configuration)"
  type        = bool
  default     = false
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
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

# Cost Management
variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection for the zero trust resources"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}