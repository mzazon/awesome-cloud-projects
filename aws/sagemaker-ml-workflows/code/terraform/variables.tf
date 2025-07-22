# Project configuration variables
variable "project_name" {
  description = "Name of the ML pipeline project"
  type        = string
  default     = "ml-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# S3 bucket configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for ML artifacts (will be suffixed with random string)"
  type        = string
  default     = "ml-pipeline-bucket"
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

# SageMaker configuration
variable "sagemaker_processing_instance_type" {
  description = "Instance type for SageMaker processing jobs"
  type        = string
  default     = "ml.m5.large"
  
  validation {
    condition = can(regex("^ml\\.[a-z0-9]+\\.(small|medium|large|xlarge|[0-9]+xlarge)$", var.sagemaker_processing_instance_type))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.m5.large)."
  }
}

variable "sagemaker_training_instance_type" {
  description = "Instance type for SageMaker training jobs"
  type        = string
  default     = "ml.m5.large"
  
  validation {
    condition = can(regex("^ml\\.[a-z0-9]+\\.(small|medium|large|xlarge|[0-9]+xlarge)$", var.sagemaker_training_instance_type))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.m5.large)."
  }
}

variable "sagemaker_endpoint_instance_type" {
  description = "Instance type for SageMaker endpoints"
  type        = string
  default     = "ml.t2.medium"
  
  validation {
    condition = can(regex("^ml\\.[a-z0-9]+\\.(small|medium|large|xlarge|[0-9]+xlarge)$", var.sagemaker_endpoint_instance_type))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.t2.medium)."
  }
}

variable "sagemaker_volume_size" {
  description = "EBS volume size in GB for SageMaker jobs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.sagemaker_volume_size >= 1 && var.sagemaker_volume_size <= 16384
    error_message = "Volume size must be between 1 and 16384 GB."
  }
}

variable "sagemaker_max_runtime_seconds" {
  description = "Maximum runtime for SageMaker training jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.sagemaker_max_runtime_seconds >= 1 && var.sagemaker_max_runtime_seconds <= 432000
    error_message = "Max runtime must be between 1 and 432000 seconds (5 days)."
  }
}

# Model evaluation configuration
variable "model_performance_threshold" {
  description = "Minimum R2 score threshold for model deployment"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.model_performance_threshold >= 0.0 && var.model_performance_threshold <= 1.0
    error_message = "Model performance threshold must be between 0.0 and 1.0."
  }
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# SNS configuration
variable "enable_sns_notifications" {
  description = "Enable SNS notifications for pipeline events"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for pipeline notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# CloudWatch configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Data generation configuration
variable "create_sample_data" {
  description = "Whether to create sample Boston Housing dataset"
  type        = bool
  default     = true
}

variable "train_test_split_ratio" {
  description = "Ratio for train/test split (e.g., 0.8 for 80% train, 20% test)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.train_test_split_ratio > 0.0 && var.train_test_split_ratio < 1.0
    error_message = "Train/test split ratio must be between 0.0 and 1.0."
  }
}