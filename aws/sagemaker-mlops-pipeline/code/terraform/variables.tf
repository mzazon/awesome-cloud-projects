# Core configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2' or similar."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "mlops-pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# SageMaker configuration
variable "model_package_group_name" {
  description = "Name for the SageMaker Model Package Group"
  type        = string
  default     = "fraud-detection-models"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9\\-]+$", var.model_package_group_name))
    error_message = "Model package group name must contain only alphanumeric characters and hyphens."
  }
}

variable "sagemaker_training_instance_type" {
  description = "Instance type for SageMaker training jobs"
  type        = string
  default     = "ml.m5.large"
  
  validation {
    condition = can(regex("^ml\\.[a-z0-9]+\\.[a-z0-9]+$", var.sagemaker_training_instance_type))
    error_message = "Instance type must be a valid SageMaker instance type (e.g., ml.m5.large)."
  }
}

variable "sagemaker_endpoint_instance_type" {
  description = "Instance type for SageMaker inference endpoints"
  type        = string
  default     = "ml.t2.medium"
  
  validation {
    condition = can(regex("^ml\\.[a-z0-9]+\\.[a-z0-9]+$", var.sagemaker_endpoint_instance_type))
    error_message = "Instance type must be a valid SageMaker instance type (e.g., ml.t2.medium)."
  }
}

# CodeBuild configuration
variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild projects"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM", 
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "Compute type must be a valid CodeBuild compute type."
  }
}

variable "codebuild_image" {
  description = "Docker image for CodeBuild projects"
  type        = string
  default     = "aws/codebuild/standard:5.0"
}

# S3 configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_days" {
  description = "Number of days after which objects transition to cheaper storage classes"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_days > 0
    error_message = "S3 lifecycle days must be a positive number."
  }
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda deployment function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda deployment function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

# Monitoring and notifications
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for pipeline notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

# Security configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and other resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Pipeline configuration
variable "github_repo_owner" {
  description = "GitHub repository owner/organization (optional - for GitHub source)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name (optional - for GitHub source)"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to trigger pipeline (optional - for GitHub source)"
  type        = string
  default     = "main"
}

# Training data configuration
variable "training_data_prefix" {
  description = "S3 prefix for training data"
  type        = string
  default     = "training-data"
}

variable "model_artifacts_prefix" {
  description = "S3 prefix for model artifacts"
  type        = string
  default     = "model-artifacts"
}

variable "pipeline_artifacts_prefix" {
  description = "S3 prefix for pipeline artifacts"
  type        = string
  default     = "pipeline-artifacts"
}

# Additional configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}