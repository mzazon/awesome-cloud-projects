# variables.tf - Input Variables for High-Performance File Systems with Amazon FSx
#
# This file defines all input variables for the Terraform configuration.
# Variables are organized by category with comprehensive validation and documentation.

# =============================================================================
# General Configuration Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-central-1, etc."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "fsx-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_prefix))
    error_message = "Project prefix must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "owner" {
  description = "Owner or team responsible for these resources"
  type        = string
  default     = "recipes-team"
}

variable "cost_center" {
  description = "Cost center for billing and chargeback"
  type        = string
  default     = "infrastructure"
}

# =============================================================================
# Networking Configuration
# =============================================================================

variable "create_vpc" {
  description = "Whether to create a new VPC or use existing VPC"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "ID of existing VPC (required if create_vpc is false)"
  type        = string
  default     = null
  
  validation {
    condition = var.vpc_id == null || can(regex("^vpc-[a-z0-9]{8,17}$", var.vpc_id))
    error_message = "VPC ID must be in the format vpc-xxxxxxxx."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if create_vpc is true)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_ids" {
  description = "List of subnet IDs for FSx file systems (required if create_vpc is false)"
  type        = list(string)
  default     = []
  
  validation {
    condition = length(var.subnet_ids) == 0 || alltrue([
      for subnet_id in var.subnet_ids : can(regex("^subnet-[a-z0-9]{8,17}$", subnet_id))
    ])
    error_message = "All subnet IDs must be in the format subnet-xxxxxxxx."
  }
}

variable "availability_zones" {
  description = "List of availability zones for subnets (only used if create_vpc is true)"
  type        = list(string)
  default     = []
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access FSx file systems"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all FSx file systems"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (if null, AWS managed key will be used)"
  type        = string
  default     = null
}

# =============================================================================
# FSx for Lustre Configuration
# =============================================================================

variable "create_lustre_filesystem" {
  description = "Whether to create FSx for Lustre file system"
  type        = bool
  default     = true
}

variable "lustre_storage_capacity" {
  description = "Storage capacity for Lustre file system in GiB (minimum 1200 for SCRATCH_2)"
  type        = number
  default     = 1200
  
  validation {
    condition     = var.lustre_storage_capacity >= 1200 && var.lustre_storage_capacity % 1200 == 0
    error_message = "Lustre storage capacity must be at least 1200 GiB and in multiples of 1200 GiB."
  }
}

variable "lustre_deployment_type" {
  description = "Deployment type for Lustre file system"
  type        = string
  default     = "SCRATCH_2"
  
  validation {
    condition     = contains(["SCRATCH_1", "SCRATCH_2", "PERSISTENT_1", "PERSISTENT_2"], var.lustre_deployment_type)
    error_message = "Lustre deployment type must be one of: SCRATCH_1, SCRATCH_2, PERSISTENT_1, PERSISTENT_2."
  }
}

variable "lustre_per_unit_storage_throughput" {
  description = "Per unit storage throughput for Lustre file system (MB/s/TiB)"
  type        = number
  default     = 250
  
  validation {
    condition     = contains([50, 100, 200, 250, 500, 1000], var.lustre_per_unit_storage_throughput)
    error_message = "Lustre per unit storage throughput must be one of: 50, 100, 200, 250, 500, 1000."
  }
}

variable "create_s3_data_repository" {
  description = "Whether to create S3 bucket for Lustre data repository"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for Lustre data repository (if null, will be generated)"
  type        = string
  default     = null
}

variable "lustre_auto_import_policy" {
  description = "Auto import policy for Lustre file system"
  type        = string
  default     = "NEW_CHANGED_DELETED"
  
  validation {
    condition     = contains(["NONE", "NEW", "NEW_CHANGED", "NEW_CHANGED_DELETED"], var.lustre_auto_import_policy)
    error_message = "Auto import policy must be one of: NONE, NEW, NEW_CHANGED, NEW_CHANGED_DELETED."
  }
}

variable "lustre_data_compression_type" {
  description = "Data compression type for Lustre file system"
  type        = string
  default     = "LZ4"
  
  validation {
    condition     = contains(["NONE", "LZ4"], var.lustre_data_compression_type)
    error_message = "Data compression type must be one of: NONE, LZ4."
  }
}

# =============================================================================
# FSx for Windows File Server Configuration
# =============================================================================

variable "create_windows_filesystem" {
  description = "Whether to create FSx for Windows File Server"
  type        = bool
  default     = true
}

variable "windows_storage_capacity" {
  description = "Storage capacity for Windows file system in GiB (minimum 32)"
  type        = number
  default     = 32
  
  validation {
    condition     = var.windows_storage_capacity >= 32 && var.windows_storage_capacity <= 65536
    error_message = "Windows storage capacity must be between 32 and 65536 GiB."
  }
}

variable "windows_throughput_capacity" {
  description = "Throughput capacity for Windows file system in MB/s"
  type        = number
  default     = 8
  
  validation {
    condition     = contains([8, 16, 32, 64, 128, 256, 512, 1024, 2048], var.windows_throughput_capacity)
    error_message = "Windows throughput capacity must be one of: 8, 16, 32, 64, 128, 256, 512, 1024, 2048."
  }
}

variable "windows_deployment_type" {
  description = "Deployment type for Windows file system"
  type        = string
  default     = "SINGLE_AZ_1"
  
  validation {
    condition     = contains(["SINGLE_AZ_1", "SINGLE_AZ_2", "MULTI_AZ_1"], var.windows_deployment_type)
    error_message = "Windows deployment type must be one of: SINGLE_AZ_1, SINGLE_AZ_2, MULTI_AZ_1."
  }
}

# =============================================================================
# FSx for NetApp ONTAP Configuration
# =============================================================================

variable "create_ontap_filesystem" {
  description = "Whether to create FSx for NetApp ONTAP file system"
  type        = bool
  default     = true
}

variable "ontap_storage_capacity" {
  description = "Storage capacity for ONTAP file system in GiB (minimum 1024)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.ontap_storage_capacity >= 1024 && var.ontap_storage_capacity <= 196608
    error_message = "ONTAP storage capacity must be between 1024 and 196608 GiB."
  }
}

variable "ontap_throughput_capacity" {
  description = "Throughput capacity for ONTAP file system in MB/s"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096], var.ontap_throughput_capacity)
    error_message = "ONTAP throughput capacity must be one of: 128, 256, 512, 1024, 2048, 4096."
  }
}

variable "ontap_deployment_type" {
  description = "Deployment type for ONTAP file system"
  type        = string
  default     = "MULTI_AZ_1"
  
  validation {
    condition     = contains(["SINGLE_AZ_1", "MULTI_AZ_1"], var.ontap_deployment_type)
    error_message = "ONTAP deployment type must be one of: SINGLE_AZ_1, MULTI_AZ_1."
  }
}

variable "ontap_admin_password" {
  description = "Admin password for ONTAP file system (if null, will be generated)"
  type        = string
  default     = null
  sensitive   = true
}

variable "create_ontap_svm" {
  description = "Whether to create Storage Virtual Machine for ONTAP"
  type        = bool
  default     = true
}

variable "ontap_svm_name" {
  description = "Name for the ONTAP Storage Virtual Machine"
  type        = string
  default     = "demo-svm"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,46}$", var.ontap_svm_name))
    error_message = "SVM name must start with a letter and be 1-47 characters long, containing only letters, numbers, underscores, and hyphens."
  }
}

variable "create_ontap_volumes" {
  description = "Whether to create volumes in the ONTAP SVM"
  type        = bool
  default     = true
}

variable "ontap_nfs_volume_size" {
  description = "Size of NFS volume in MiB"
  type        = number
  default     = 102400
  
  validation {
    condition     = var.ontap_nfs_volume_size >= 20 && var.ontap_nfs_volume_size <= 104857600
    error_message = "NFS volume size must be between 20 MiB and 100 TiB (104857600 MiB)."
  }
}

variable "ontap_smb_volume_size" {
  description = "Size of SMB volume in MiB"
  type        = number
  default     = 51200
  
  validation {
    condition     = var.ontap_smb_volume_size >= 20 && var.ontap_smb_volume_size <= 104857600
    error_message = "SMB volume size must be between 20 MiB and 100 TiB (104857600 MiB)."
  }
}

# =============================================================================
# Monitoring and Alerting Configuration
# =============================================================================

variable "create_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "sns_notification_email" {
  description = "Email address for CloudWatch alarm notifications (if null, SNS topic won't be created)"
  type        = string
  default     = null
  
  validation {
    condition = var.sns_notification_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.sns_notification_email))
    error_message = "SNS notification email must be a valid email address."
  }
}

variable "alarm_threshold_lustre_throughput" {
  description = "Threshold for Lustre throughput utilization alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.alarm_threshold_lustre_throughput >= 0 && var.alarm_threshold_lustre_throughput <= 100
    error_message = "Alarm threshold must be between 0 and 100."
  }
}

variable "alarm_threshold_windows_cpu" {
  description = "Threshold for Windows file system CPU utilization alarm (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.alarm_threshold_windows_cpu >= 0 && var.alarm_threshold_windows_cpu <= 100
    error_message = "Alarm threshold must be between 0 and 100."
  }
}

variable "alarm_threshold_ontap_storage" {
  description = "Threshold for ONTAP storage utilization alarm (percentage)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.alarm_threshold_ontap_storage >= 0 && var.alarm_threshold_ontap_storage <= 100
    error_message = "Alarm threshold must be between 0 and 100."
  }
}

# =============================================================================
# Backup Configuration
# =============================================================================

variable "enable_automatic_backups" {
  description = "Whether to enable automatic backups for file systems"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automatic backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 90
    error_message = "Backup retention days must be between 0 and 90."
  }
}

variable "daily_backup_start_time" {
  description = "Daily backup start time in UTC (HH:MM format)"
  type        = string
  default     = "01:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.daily_backup_start_time))
    error_message = "Daily backup start time must be in HH:MM format (24-hour)."
  }
}

# =============================================================================
# Testing and Demo Configuration
# =============================================================================

variable "create_test_instances" {
  description = "Whether to create EC2 instances for testing file system access"
  type        = bool
  default     = false
}

variable "test_instance_type" {
  description = "Instance type for test EC2 instances"
  type        = string
  default     = "t3.medium"
}

variable "test_instance_key_name" {
  description = "EC2 Key Pair name for test instances (required if create_test_instances is true)"
  type        = string
  default     = null
}