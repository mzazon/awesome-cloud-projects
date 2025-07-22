# =============================================================================
# Variables for S3 Cross-Region Replication with Encryption and Access Controls
# =============================================================================

# Project configuration
variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "s3-crr"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Project     = "S3-Cross-Region-Replication"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# Region Configuration
# =============================================================================

variable "source_region" {
  description = "AWS region for the source S3 bucket"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.source_region))
    error_message = "Source region must be a valid AWS region identifier."
  }
}

variable "destination_region" {
  description = "AWS region for the destination S3 bucket"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.destination_region))
    error_message = "Destination region must be a valid AWS region identifier."
  }
}

# =============================================================================
# S3 Bucket Configuration
# =============================================================================

variable "source_bucket_name" {
  description = "Base name for the source S3 bucket (random suffix will be added)"
  type        = string
  default     = "crr-source"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.source_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "destination_bucket_name" {
  description = "Base name for the destination S3 bucket (random suffix will be added)"
  type        = string
  default     = "crr-destination"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.destination_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy S3 buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "replication_storage_class" {
  description = "Storage class for replicated objects in the destination bucket"
  type        = string
  default     = "STANDARD_IA"
  
  validation {
    condition = contains([
      "STANDARD",
      "REDUCED_REDUNDANCY", 
      "STANDARD_IA",
      "ONEZONE_IA",
      "INTELLIGENT_TIERING",
      "GLACIER",
      "DEEP_ARCHIVE"
    ], var.replication_storage_class)
    error_message = "Replication storage class must be a valid S3 storage class."
  }
}

# =============================================================================
# KMS Configuration
# =============================================================================

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS keys (7-30 days)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for replication"
  type        = bool
  default     = true
}

variable "enable_size_monitoring" {
  description = "Enable monitoring for source bucket size (requires enable_monitoring = true)"
  type        = bool
  default     = false
}

variable "replication_latency_threshold" {
  description = "Threshold in seconds for replication latency alarm (default: 900 = 15 minutes)"
  type        = number
  default     = 900
  
  validation {
    condition     = var.replication_latency_threshold > 0
    error_message = "Replication latency threshold must be greater than 0."
  }
}

variable "bucket_size_threshold" {
  description = "Threshold in bytes for source bucket size alarm (default: 1GB)"
  type        = number
  default     = 1000000000
  
  validation {
    condition     = var.bucket_size_threshold > 0
    error_message = "Bucket size threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods > 0
    error_message = "Alarm evaluation periods must be greater than 0."
  }
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
  
  validation {
    condition = contains([60, 300, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be 60, 300, 900, or 3600 seconds."
  }
}

# =============================================================================
# Access Control Configuration
# =============================================================================

variable "enable_bucket_policies" {
  description = "Enable bucket policies for additional security controls"
  type        = bool
  default     = true
}

variable "enable_public_access_block" {
  description = "Enable S3 public access block settings"
  type        = bool
  default     = true
}

# =============================================================================
# Advanced Configuration
# =============================================================================

variable "replication_prefix_filter" {
  description = "Object prefix filter for replication (empty string replicates all objects)"
  type        = string
  default     = ""
}

variable "enable_delete_marker_replication" {
  description = "Enable replication of delete markers"
  type        = bool
  default     = true
}

variable "enable_sse_kms_encrypted_objects" {
  description = "Enable replication of SSE-KMS encrypted objects only"
  type        = bool
  default     = true
}

# =============================================================================
# Cost Optimization
# =============================================================================

variable "enable_bucket_key" {
  description = "Enable S3 Bucket Key for cost optimization with KMS"
  type        = bool
  default     = true
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering on destination bucket for cost optimization"
  type        = bool
  default     = false
}

# =============================================================================
# Compliance and Governance
# =============================================================================

variable "enable_object_lock" {
  description = "Enable S3 Object Lock on destination bucket for compliance"
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object lock mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
  
  validation {
    condition = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "Object lock mode must be either GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retain_days" {
  description = "Number of days to retain objects when object lock is enabled"
  type        = number
  default     = 30
  
  validation {
    condition     = var.object_lock_retain_days > 0
    error_message = "Object lock retention days must be greater than 0."
  }
}