# Environment and project configuration
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
  description = "Name of the MLOps project"
  type        = string
  default     = "mlops-sagemaker"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# S3 bucket configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_force_destroy" {
  description = "Allow destruction of S3 bucket with objects"
  type        = bool
  default     = false
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

# CodeCommit repository configuration
variable "codecommit_repo_name" {
  description = "Name for the CodeCommit repository (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "codecommit_repo_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "MLOps pipeline code repository for machine learning workflows"
}

# SageMaker configuration
variable "pipeline_name" {
  description = "Name for the SageMaker pipeline (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "sagemaker_execution_role_name" {
  description = "Name for the SageMaker execution role (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "training_instance_type" {
  description = "Instance type for SageMaker training jobs"
  type        = string
  default     = "ml.m5.large"
  
  validation {
    condition = can(regex("^ml\\.", var.training_instance_type))
    error_message = "Training instance type must be a valid SageMaker ML instance type."
  }
}

variable "processing_instance_type" {
  description = "Instance type for SageMaker processing jobs"
  type        = string
  default     = "ml.m5.large"
  
  validation {
    condition = can(regex("^ml\\.", var.processing_instance_type))
    error_message = "Processing instance type must be a valid SageMaker ML instance type."
  }
}

variable "sklearn_framework_version" {
  description = "Scikit-learn framework version for SageMaker"
  type        = string
  default     = "0.23-1"
}

# Model configuration
variable "model_name" {
  description = "Name for the ML model (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "model_package_group_name" {
  description = "Name for the SageMaker Model Package Group (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# Security and access configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and SageMaker resources"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (leave empty to use default AWS managed keys)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for SageMaker resources (leave empty for default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for SageMaker resources (leave empty for default subnets)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for SageMaker resources"
  type        = list(string)
  default     = []
}

# Pipeline configuration
variable "pipeline_parameters" {
  description = "Default parameters for the SageMaker pipeline"
  type = object({
    input_data_path       = string
    output_model_path     = string
    training_data_path    = string
    validation_data_path  = string
  })
  default = {
    input_data_path      = "data/"
    output_model_path    = "models/"
    training_data_path   = "data/train.csv"
    validation_data_path = "data/validation.csv"
  }
}

# Monitoring and logging
variable "enable_model_monitoring" {
  description = "Enable SageMaker Model Monitor"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}