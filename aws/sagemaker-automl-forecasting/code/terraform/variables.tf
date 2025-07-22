# General Configuration Variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "automl-forecasting"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_force_destroy" {
  description = "Allow forceful deletion of S3 bucket (use with caution in production)"
  type        = bool
  default     = false
}

# SageMaker Configuration
variable "sagemaker_instance_type" {
  description = "Instance type for SageMaker endpoint"
  type        = string
  default     = "ml.m5.large"

  validation {
    condition = can(regex("^ml\\.", var.sagemaker_instance_type))
    error_message = "SageMaker instance type must start with 'ml.'."
  }
}

variable "automl_max_runtime_seconds" {
  description = "Maximum runtime in seconds for AutoML job"
  type        = number
  default     = 14400 # 4 hours
  
  validation {
    condition     = var.automl_max_runtime_seconds >= 3600 && var.automl_max_runtime_seconds <= 86400
    error_message = "AutoML max runtime must be between 1 hour (3600) and 24 hours (86400) seconds."
  }
}

variable "forecast_horizon" {
  description = "Number of days to forecast into the future"
  type        = number
  default     = 14

  validation {
    condition     = var.forecast_horizon >= 1 && var.forecast_horizon <= 500
    error_message = "Forecast horizon must be between 1 and 500 days."
  }
}

variable "forecast_quantiles" {
  description = "Quantiles for forecast confidence intervals"
  type        = list(string)
  default     = ["0.1", "0.5", "0.9"]
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
}

# CloudWatch Configuration
variable "cloudwatch_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid value."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and other resources"
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

# Training Data Configuration
variable "training_data_s3_prefix" {
  description = "S3 prefix for training data files"
  type        = string
  default     = "training-data"
}

variable "automl_output_s3_prefix" {
  description = "S3 prefix for AutoML job outputs"
  type        = string
  default     = "automl-output"
}

# Model Configuration
variable "model_approval_status" {
  description = "Approval status for registered models"
  type        = string
  default     = "Approved"

  validation {
    condition     = contains(["Approved", "Rejected", "PendingManualApproval"], var.model_approval_status)
    error_message = "Model approval status must be Approved, Rejected, or PendingManualApproval."
  }
}

# Endpoint Configuration
variable "endpoint_initial_instance_count" {
  description = "Initial number of instances for SageMaker endpoint"
  type        = number
  default     = 1

  validation {
    condition     = var.endpoint_initial_instance_count >= 1
    error_message = "Endpoint instance count must be at least 1."
  }
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling for SageMaker endpoint"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Data Generation Configuration
variable "generate_sample_data" {
  description = "Generate sample training data for testing"
  type        = bool
  default     = true
}

variable "sample_data_items" {
  description = "Number of unique items in sample dataset"
  type        = number
  default     = 25

  validation {
    condition     = var.sample_data_items >= 1 && var.sample_data_items <= 1000
    error_message = "Sample data items must be between 1 and 1000."
  }
}

variable "sample_data_days" {
  description = "Number of days of historical data to generate"
  type        = number
  default     = 1095 # 3 years

  validation {
    condition     = var.sample_data_days >= 365 && var.sample_data_days <= 3650
    error_message = "Sample data days must be between 365 and 3650 (1-10 years)."
  }
}