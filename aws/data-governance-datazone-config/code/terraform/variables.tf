# Input variables for the data governance pipeline

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

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
  description = "Name of the project for resource naming"
  type        = string
  default     = "data-governance"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "datazone_domain_name" {
  description = "Name for the Amazon DataZone domain"
  type        = string
  default     = ""
}

variable "datazone_project_name" {
  description = "Name for the DataZone project"
  type        = string
  default     = ""
}

variable "config_bucket_prefix" {
  description = "Prefix for the AWS Config S3 bucket name"
  type        = string
  default     = "aws-config-bucket"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_config_aggregator" {
  description = "Whether to enable AWS Config aggregator for multi-account compliance"
  type        = bool
  default     = false
}

variable "sns_email_endpoint" {
  description = "Email address for governance alert notifications"
  type        = string
  default     = ""

  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "Email address must be a valid email format or empty string."
  }
}

variable "config_rules" {
  description = "List of AWS Config rules to deploy for data governance"
  type = list(object({
    name                = string
    description         = string
    source_identifier   = string
    resource_types      = list(string)
  }))
  default = [
    {
      name              = "s3-bucket-server-side-encryption-enabled"
      description       = "Checks if S3 buckets have server-side encryption enabled"
      source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
      resource_types    = ["AWS::S3::Bucket"]
    },
    {
      name              = "rds-storage-encrypted"
      description       = "Checks if RDS instances have storage encryption enabled"
      source_identifier = "RDS_STORAGE_ENCRYPTED"
      resource_types    = ["AWS::RDS::DBInstance"]
    },
    {
      name              = "s3-bucket-public-read-prohibited"
      description       = "Checks if S3 buckets prohibit public read access"
      source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
      resource_types    = ["AWS::S3::Bucket"]
    }
  ]
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold values for CloudWatch alarms"
  type = object({
    lambda_errors     = number
    lambda_duration   = number
    compliance_ratio  = number
  })
  default = {
    lambda_errors     = 1
    lambda_duration   = 240000
    compliance_ratio  = 0.8
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}