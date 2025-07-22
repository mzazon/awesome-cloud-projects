# Input variables for secure file sharing with AWS Transfer Family

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "test", "staging", "prod"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "secure-file-sharing"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket names (random suffix will be added)"
  type        = string
  default     = "secure-files"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "transfer_server_endpoint_type" {
  description = "Transfer server endpoint type"
  type        = string
  default     = "PUBLIC"
  validation {
    condition = contains([
      "PUBLIC", "VPC", "VPC_ENDPOINT"
    ], var.transfer_server_endpoint_type)
    error_message = "Endpoint type must be one of: PUBLIC, VPC, VPC_ENDPOINT."
  }
}

variable "transfer_protocols" {
  description = "List of protocols to enable for Transfer Family server"
  type        = list(string)
  default     = ["SFTP"]
  validation {
    condition = length(var.transfer_protocols) > 0 && alltrue([
      for protocol in var.transfer_protocols : contains(["SFTP", "FTPS", "FTP"], protocol)
    ])
    error_message = "At least one protocol must be specified, and all protocols must be one of: SFTP, FTPS, FTP."
  }
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Number of days to retain CloudTrail logs in CloudWatch"
  type        = number
  default     = 30
  validation {
    condition     = var.cloudtrail_log_retention_days >= 1 && var.cloudtrail_log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

variable "s3_lifecycle_enable" {
  description = "Enable S3 lifecycle management for cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days after which to transition objects to Infrequent Access"
  type        = number
  default     = 30
  validation {
    condition     = var.s3_transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days after which to transition objects to Glacier"
  type        = number
  default     = 90
  validation {
    condition     = var.s3_transition_to_glacier_days >= 30
    error_message = "Transition to Glacier must be at least 30 days."
  }
}

variable "enable_sso_integration" {
  description = "Enable IAM Identity Center (SSO) integration"
  type        = bool
  default     = false
}

variable "test_user_name" {
  description = "Username for test user creation"
  type        = string
  default     = "testuser"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.test_user_name))
    error_message = "Test user name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "test_user_home_directory" {
  description = "Home directory path for test user"
  type        = string
  default     = "/"
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS keys"
  type        = number
  default     = 10
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_multi_factor_auth" {
  description = "Enable multi-factor authentication requirements"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Transfer Family endpoints"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backup files"
  type        = number
  default     = 365
  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Backup retention days must be at least 1."
  }
}