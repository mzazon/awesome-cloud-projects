# AWS Region
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}(-[a-z]{2})?-[a-z]+-[0-9]{1,2}$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

# Environment name
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Project name prefix
variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
  default     = "automl-sagemaker"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# AutoML Job Configuration
variable "autopilot_job_config" {
  description = "Configuration for SageMaker Autopilot job"
  type = object({
    max_candidates                     = number
    max_runtime_per_training_job       = number
    max_automl_job_runtime            = number
    problem_type                      = string
    target_attribute_name             = string
    completion_criteria_metric_name   = string
  })
  default = {
    max_candidates                     = 10
    max_runtime_per_training_job       = 3600
    max_automl_job_runtime            = 14400
    problem_type                      = "BinaryClassification"
    target_attribute_name             = "churn"
    completion_criteria_metric_name   = "F1"
  }
  
  validation {
    condition = contains(["BinaryClassification", "MulticlassClassification", "Regression"], var.autopilot_job_config.problem_type)
    error_message = "Problem type must be one of: BinaryClassification, MulticlassClassification, Regression."
  }
}

# S3 Bucket Configuration
variable "s3_bucket_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

variable "s3_bucket_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

# Model Deployment Configuration
variable "deploy_endpoint" {
  description = "Whether to deploy a real-time inference endpoint"
  type        = bool
  default     = false
}

variable "endpoint_config" {
  description = "Configuration for SageMaker endpoint"
  type = object({
    instance_type   = string
    instance_count  = number
    variant_name    = string
  })
  default = {
    instance_type   = "ml.m5.large"
    instance_count  = 1
    variant_name    = "primary"
  }
}

# Sample Dataset Configuration
variable "create_sample_dataset" {
  description = "Whether to create and upload sample dataset"
  type        = bool
  default     = true
}

variable "sample_dataset_config" {
  description = "Configuration for sample dataset"
  type = object({
    filename = string
    content_type = string
  })
  default = {
    filename = "churn_dataset.csv"
    content_type = "text/csv"
  }
}

# IAM Role Configuration
variable "iam_role_config" {
  description = "Configuration for IAM role"
  type = object({
    create_role = bool
    role_name   = string
    role_arn    = string
  })
  default = {
    create_role = true
    role_name   = ""
    role_arn    = ""
  }
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Enable KMS encryption
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 bucket and SageMaker resources"
  type        = bool
  default     = false
}

# VPC Configuration (optional)
variable "vpc_config" {
  description = "VPC configuration for SageMaker resources"
  type = object({
    enable_vpc           = bool
    vpc_id              = string
    subnet_ids          = list(string)
    security_group_ids  = list(string)
  })
  default = {
    enable_vpc           = false
    vpc_id              = ""
    subnet_ids          = []
    security_group_ids  = []
  }
}

# Data Quality Configuration
variable "data_quality_config" {
  description = "Configuration for data quality checks"
  type = object({
    enable_data_quality_job = bool
    schedule_expression     = string
  })
  default = {
    enable_data_quality_job = false
    schedule_expression     = "rate(7 days)"
  }
}