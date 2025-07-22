# =========================================
# Core Configuration Variables
# =========================================

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "edge-ai-inference"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# =========================================
# S3 Configuration Variables
# =========================================

variable "model_bucket_versioning" {
  description = "Enable versioning for the model storage bucket"
  type        = bool
  default     = true
}

variable "model_bucket_lifecycle_enabled" {
  description = "Enable lifecycle management for model bucket"
  type        = bool
  default     = true
}

variable "model_bucket_noncurrent_version_expiration" {
  description = "Days after which noncurrent versions will be deleted"
  type        = number
  default     = 30
  
  validation {
    condition     = var.model_bucket_noncurrent_version_expiration > 0
    error_message = "Noncurrent version expiration must be greater than 0 days."
  }
}

# =========================================
# IoT Greengrass Configuration Variables
# =========================================

variable "greengrass_thing_name" {
  description = "Name for the IoT Greengrass thing"
  type        = string
  default     = ""
}

variable "greengrass_core_device_type" {
  description = "Type of the Greengrass core device"
  type        = string
  default     = "edge-inference-device"
}

variable "enable_greengrass_logging" {
  description = "Enable CloudWatch logging for Greengrass"
  type        = bool
  default     = true
}

# =========================================
# EventBridge Configuration Variables
# =========================================

variable "event_bus_name" {
  description = "Name for the custom EventBridge bus"
  type        = string
  default     = "edge-monitoring-bus"
}

variable "enable_event_replay" {
  description = "Enable event replay capability for EventBridge"
  type        = bool
  default     = false
}

# =========================================
# Component Configuration Variables
# =========================================

variable "onnx_runtime_version" {
  description = "Version of ONNX Runtime to install"
  type        = string
  default     = "1.16.0"
}

variable "inference_interval_seconds" {
  description = "Interval between inference runs in seconds"
  type        = number
  default     = 10
  
  validation {
    condition     = var.inference_interval_seconds >= 1
    error_message = "Inference interval must be at least 1 second."
  }
}

variable "confidence_threshold" {
  description = "Minimum confidence threshold for inference results"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.confidence_threshold >= 0.0 && var.confidence_threshold <= 1.0
    error_message = "Confidence threshold must be between 0.0 and 1.0."
  }
}

# =========================================
# Model Configuration Variables
# =========================================

variable "model_name" {
  description = "Name of the machine learning model"
  type        = string
  default     = "defect_detection_v1"
}

variable "model_version" {
  description = "Version of the machine learning model"
  type        = string
  default     = "1.0.0"
}

variable "model_framework" {
  description = "ML framework used for the model"
  type        = string
  default     = "onnx"
  
  validation {
    condition     = contains(["onnx", "tensorflow", "pytorch"], var.model_framework)
    error_message = "Model framework must be one of: onnx, tensorflow, pytorch."
  }
}

# =========================================
# Security Configuration Variables
# =========================================

variable "enable_s3_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_kms_key_id" {
  description = "KMS key ID for S3 encryption (optional)"
  type        = string
  default     = null
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for API calls"
  type        = bool
  default     = false
}

# =========================================
# Monitoring Configuration Variables
# =========================================

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for components"
  type        = bool
  default     = false
}

# =========================================
# Resource Tagging Variables
# =========================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =========================================
# Cost Optimization Variables
# =========================================

variable "s3_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = false
}

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for billing"
  type        = bool
  default     = true
}