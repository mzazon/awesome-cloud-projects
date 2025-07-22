# Input variables for the cross-account compliance monitoring solution

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "security_account_id" {
  description = "AWS Account ID for the Security Hub administrator account"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "Security account ID must be a 12-digit AWS account ID."
  }
}

variable "member_account_1" {
  description = "AWS Account ID for the first member account"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.member_account_1))
    error_message = "Member account 1 ID must be a 12-digit AWS account ID."
  }
}

variable "member_account_2" {
  description = "AWS Account ID for the second member account"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.member_account_2))
    error_message = "Member account 2 ID must be a 12-digit AWS account ID."
  }
}

variable "additional_member_accounts" {
  description = "List of additional member account IDs for compliance monitoring"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for account in var.additional_member_accounts : can(regex("^[0-9]{12}$", account))
    ])
    error_message = "All additional member account IDs must be 12-digit AWS account IDs."
  }
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for compliance auditing"
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in CloudWatch"
  type        = number
  default     = 90
  
  validation {
    condition     = var.cloudtrail_log_retention_days >= 1 && var.cloudtrail_log_retention_days <= 3653
    error_message = "CloudTrail log retention must be between 1 and 3653 days."
  }
}

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
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_security_standards" {
  description = "List of Security Hub standards to enable"
  type        = list(string)
  default     = ["aws-foundational", "cis-aws-foundations-benchmark", "pci-dss"]
  
  validation {
    condition = alltrue([
      for standard in var.enable_security_standards : 
      contains(["aws-foundational", "cis-aws-foundations-benchmark", "pci-dss"], standard)
    ])
    error_message = "Security standards must be one of: aws-foundational, cis-aws-foundations-benchmark, pci-dss."
  }
}

variable "compliance_check_schedule" {
  description = "Schedule expression for Systems Manager compliance checks"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.compliance_check_schedule))
    error_message = "Compliance check schedule must be a valid rate or cron expression."
  }
}

variable "external_id" {
  description = "External ID for cross-account role assumption (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_custom_compliance" {
  description = "Enable custom compliance checks for organizational policies"
  type        = bool
  default     = true
}

variable "required_tags" {
  description = "List of required tags for custom compliance checks"
  type        = list(string)
  default     = ["Environment", "Owner", "Project"]
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names (must be globally unique)"
  type        = string
  default     = "compliance-audit-trail"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 and CloudWatch logs"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for compliance violation notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "patch_baseline_operating_systems" {
  description = "List of operating systems for patch baseline configuration"
  type        = list(string)
  default     = ["AMAZON_LINUX_2", "UBUNTU", "WINDOWS"]
  
  validation {
    condition = alltrue([
      for os in var.patch_baseline_operating_systems : 
      contains(["AMAZON_LINUX", "AMAZON_LINUX_2", "UBUNTU", "REDHAT_ENTERPRISE_LINUX", "SUSE", "CENTOS", "ORACLE_LINUX", "DEBIAN", "WINDOWS"], os)
    ])
    error_message = "Operating systems must be valid Systems Manager patch baseline OS types."
  }
}