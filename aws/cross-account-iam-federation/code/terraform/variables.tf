# Variables for Advanced Cross-Account IAM Role Federation
# These variables define the configurable parameters for the infrastructure

variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "security_account_id" {
  type        = string
  description = "AWS account ID for the security/central account that hosts the master roles"
  
  validation {
    condition = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "Security account ID must be a 12-digit AWS account ID."
  }
}

variable "production_account_id" {
  type        = string
  description = "AWS account ID for the production account"
  
  validation {
    condition = can(regex("^[0-9]{12}$", var.production_account_id))
    error_message = "Production account ID must be a 12-digit AWS account ID."
  }
}

variable "development_account_id" {
  type        = string
  description = "AWS account ID for the development account"
  
  validation {
    condition = can(regex("^[0-9]{12}$", var.development_account_id))
    error_message = "Development account ID must be a 12-digit AWS account ID."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., security, production, development)"
  default     = "security"
  
  validation {
    condition = contains(["security", "production", "development", "staging"], var.environment)
    error_message = "Environment must be one of: security, production, development, staging."
  }
}

variable "project_name" {
  type        = string
  description = "Name of the project for resource naming and tagging"
  default     = "cross-account-iam-federation"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "identity_provider_name" {
  type        = string
  description = "Name of the SAML identity provider"
  default     = "CorporateIdP"
}

variable "saml_provider_arn" {
  type        = string
  description = "ARN of the SAML identity provider in the security account"
  default     = ""
}

variable "allowed_departments" {
  type        = list(string)
  description = "List of departments allowed to assume cross-account roles"
  default     = ["Engineering", "Security", "DevOps"]
}

variable "allowed_source_ips" {
  type        = list(string)
  description = "List of IP address ranges allowed for cross-account access (CIDR notation)"
  default     = ["203.0.113.0/24", "198.51.100.0/24"]
  
  validation {
    condition = alltrue([
      for ip in var.allowed_source_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All IP addresses must be in valid CIDR notation."
  }
}

variable "max_session_duration_master" {
  type        = number
  description = "Maximum session duration for master role in seconds"
  default     = 7200
  
  validation {
    condition = var.max_session_duration_master >= 3600 && var.max_session_duration_master <= 43200
    error_message = "Max session duration must be between 3600 and 43200 seconds (1-12 hours)."
  }
}

variable "max_session_duration_production" {
  type        = number
  description = "Maximum session duration for production role in seconds"
  default     = 3600
  
  validation {
    condition = var.max_session_duration_production >= 3600 && var.max_session_duration_production <= 43200
    error_message = "Max session duration must be between 3600 and 43200 seconds (1-12 hours)."
  }
}

variable "max_session_duration_development" {
  type        = number
  description = "Maximum session duration for development role in seconds"
  default     = 7200
  
  validation {
    condition = var.max_session_duration_development >= 3600 && var.max_session_duration_development <= 43200
    error_message = "Max session duration must be between 3600 and 43200 seconds (1-12 hours)."
  }
}

variable "enable_cloudtrail_logging" {
  type        = bool
  description = "Enable CloudTrail logging for cross-account activities"
  default     = true
}

variable "cloudtrail_log_retention_days" {
  type        = number
  description = "Number of days to retain CloudTrail logs"
  default     = 90
  
  validation {
    condition = var.cloudtrail_log_retention_days >= 1 && var.cloudtrail_log_retention_days <= 3653
    error_message = "CloudTrail log retention must be between 1 and 3653 days."
  }
}

variable "enable_role_validation" {
  type        = bool
  description = "Enable automated role validation using Lambda"
  default     = true
}

variable "lambda_runtime" {
  type        = string
  description = "Runtime for the role validation Lambda function"
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "production_s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for production account access (will be suffixed with random string)"
  default     = "prod-shared-data"
}

variable "development_s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for development account access (will be suffixed with random string)"
  default     = "dev-shared-data"
}

variable "enable_mfa_requirement" {
  type        = bool
  description = "Require MFA for role assumption"
  default     = true
}

variable "mfa_max_age_seconds" {
  type        = number
  description = "Maximum age of MFA token in seconds"
  default     = 3600
  
  validation {
    condition = var.mfa_max_age_seconds >= 900 && var.mfa_max_age_seconds <= 7200
    error_message = "MFA max age must be between 900 and 7200 seconds (15 minutes to 2 hours)."
  }
}

variable "enable_ip_restrictions" {
  type        = bool
  description = "Enable IP address restrictions for development account access"
  default     = true
}

variable "enable_session_tagging" {
  type        = bool
  description = "Enable session tagging for cross-account role assumptions"
  default     = true
}

variable "transitive_tag_keys" {
  type        = list(string)
  description = "List of session tag keys that can be passed transitively"
  default     = ["Department", "Project", "Environment"]
}