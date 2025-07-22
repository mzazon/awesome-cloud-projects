# Variables for AWS Storage Gateway hybrid cloud storage infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "gateway_name" {
  description = "Name for the Storage Gateway"
  type        = string
  default     = "hybrid-storage-gateway"

  validation {
    condition = length(var.gateway_name) > 0 && length(var.gateway_name) <= 255
    error_message = "Gateway name must be between 1 and 255 characters."
  }
}

variable "gateway_instance_type" {
  description = "EC2 instance type for the Storage Gateway"
  type        = string
  default     = "m5.large"

  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.[a-z]+$", var.gateway_instance_type))
    error_message = "Instance type must be a valid EC2 instance type (e.g., m5.large)."
  }
}

variable "gateway_timezone" {
  description = "Timezone for the Storage Gateway"
  type        = string
  default     = "GMT-5:00"

  validation {
    condition = can(regex("^GMT[+-][0-9]{1,2}:[0-9]{2}$", var.gateway_timezone))
    error_message = "Timezone must be in GMT format (e.g., GMT-5:00)."
  }
}

variable "cache_disk_size" {
  description = "Size of the cache disk in GB for Storage Gateway"
  type        = number
  default     = 100

  validation {
    condition = var.cache_disk_size >= 20 && var.cache_disk_size <= 16384
    error_message = "Cache disk size must be between 20 GB and 16384 GB."
  }
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket (leave empty for auto-generation)"
  type        = string
  default     = ""

  validation {
    condition = var.s3_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must follow AWS naming conventions (lowercase, numbers, dots, hyphens)."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "nfs_client_cidrs" {
  description = "List of CIDR blocks allowed to access NFS file shares"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition = length(var.nfs_client_cidrs) > 0
    error_message = "At least one CIDR block must be specified for NFS access."
  }
}

variable "enable_smb_share" {
  description = "Enable creation of SMB file share"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring for Storage Gateway"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key (7-30 days)"
  type        = number
  default     = 7

  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "vpc_id" {
  description = "VPC ID where Storage Gateway will be deployed (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID where Storage Gateway will be deployed (leave empty for auto-selection)"
  type        = string
  default     = ""
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access Storage Gateway ports"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = length(var.allowed_ingress_cidrs) > 0
    error_message = "At least one CIDR block must be specified for ingress access."
  }
}

variable "default_storage_class" {
  description = "Default S3 storage class for file shares"
  type        = string
  default     = "S3_STANDARD"

  validation {
    condition = contains([
      "S3_STANDARD",
      "S3_STANDARD_IA",
      "S3_ONEZONE_IA",
      "S3_REDUCED_REDUNDANCY"
    ], var.default_storage_class)
    error_message = "Storage class must be one of: S3_STANDARD, S3_STANDARD_IA, S3_ONEZONE_IA, S3_REDUCED_REDUNDANCY."
  }
}