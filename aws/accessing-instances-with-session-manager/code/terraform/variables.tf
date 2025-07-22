# Variable definitions for Session Manager secure access infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "session-manager-demo"
}

variable "instance_type" {
  description = "EC2 instance type for the demo instance"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = can(regex("^[t-z][0-9][a-z]?\\.[a-z]+$", var.instance_type))
    error_message = "The instance_type must be a valid EC2 instance type (e.g., t3.micro, t3.small)."
  }
}

variable "enable_logging" {
  description = "Enable Session Manager logging to CloudWatch and S3"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "s3_log_prefix" {
  description = "S3 key prefix for session logs"
  type        = string
  default     = "session-logs/"
}

variable "allowed_users" {
  description = "List of IAM users/roles allowed to start sessions"
  type        = list(string)
  default     = []
}

variable "instance_tags" {
  description = "Additional tags to apply to EC2 instances"
  type        = map(string)
  default = {
    Purpose = "SessionManagerTesting"
  }
}

variable "vpc_id" {
  description = "VPC ID to deploy the instance into (optional - uses default VPC if not specified)"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Subnet ID to deploy the instance into (optional - uses default subnet if not specified)"
  type        = string
  default     = null
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for Session Manager API calls"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}