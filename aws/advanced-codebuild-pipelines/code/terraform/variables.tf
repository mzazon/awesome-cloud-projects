# Project and environment configuration
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "advanced-build"
  
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

# AWS region configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# S3 bucket configuration
variable "cache_bucket_name" {
  description = "Name for S3 cache bucket (if empty, will be auto-generated)"
  type        = string
  default     = ""
}

variable "artifact_bucket_name" {
  description = "Name for S3 artifact bucket (if empty, will be auto-generated)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "cache_lifecycle_days" {
  description = "Number of days to retain cache objects"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cache_lifecycle_days >= 1 && var.cache_lifecycle_days <= 365
    error_message = "Cache lifecycle days must be between 1 and 365."
  }
}

variable "dependency_cache_days" {
  description = "Number of days to retain dependency cache objects"
  type        = number
  default     = 90
  
  validation {
    condition     = var.dependency_cache_days >= 1 && var.dependency_cache_days <= 365
    error_message = "Dependency cache days must be between 1 and 365."
  }
}

# ECR configuration
variable "ecr_repository_name" {
  description = "Name for ECR repository (if empty, will be auto-generated)"
  type        = string
  default     = ""
}

variable "enable_ecr_scan_on_push" {
  description = "Enable vulnerability scanning on ECR push"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_lifecycle_count_number" {
  description = "Number of tagged images to keep in ECR"
  type        = number
  default     = 10
  
  validation {
    condition     = var.ecr_lifecycle_count_number >= 1 && var.ecr_lifecycle_count_number <= 100
    error_message = "ECR lifecycle count must be between 1 and 100."
  }
}

# CodeBuild configuration
variable "codebuild_compute_types" {
  description = "Compute types for different CodeBuild projects"
  type = object({
    dependency = string
    main       = string
    parallel   = string
  })
  default = {
    dependency = "BUILD_GENERAL1_MEDIUM"
    main       = "BUILD_GENERAL1_LARGE"
    parallel   = "BUILD_GENERAL1_MEDIUM"
  }
  
  validation {
    condition = alltrue([
      contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.codebuild_compute_types.dependency),
      contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.codebuild_compute_types.main),
      contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.codebuild_compute_types.parallel)
    ])
    error_message = "Invalid CodeBuild compute type specified."
  }
}

variable "codebuild_image" {
  description = "Docker image for CodeBuild projects"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
}

variable "codebuild_timeout_minutes" {
  description = "Timeout in minutes for CodeBuild projects"
  type = object({
    dependency = number
    main       = number
    parallel   = number
  })
  default = {
    dependency = 30
    main       = 60
    parallel   = 45
  }
  
  validation {
    condition = alltrue([
      var.codebuild_timeout_minutes.dependency >= 5 && var.codebuild_timeout_minutes.dependency <= 480,
      var.codebuild_timeout_minutes.main >= 5 && var.codebuild_timeout_minutes.main <= 480,
      var.codebuild_timeout_minutes.parallel >= 5 && var.codebuild_timeout_minutes.parallel <= 480
    ])
    error_message = "CodeBuild timeout must be between 5 and 480 minutes."
  }
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout_seconds" {
  description = "Timeout in seconds for Lambda functions"
  type = object({
    orchestrator = number
    cache_manager = number
    analytics    = number
  })
  default = {
    orchestrator  = 900
    cache_manager = 300
    analytics     = 900
  }
  
  validation {
    condition = alltrue([
      var.lambda_timeout_seconds.orchestrator >= 1 && var.lambda_timeout_seconds.orchestrator <= 900,
      var.lambda_timeout_seconds.cache_manager >= 1 && var.lambda_timeout_seconds.cache_manager <= 900,
      var.lambda_timeout_seconds.analytics >= 1 && var.lambda_timeout_seconds.analytics <= 900
    ])
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type = object({
    orchestrator  = number
    cache_manager = number
    analytics     = number
  })
  default = {
    orchestrator  = 512
    cache_manager = 256
    analytics     = 512
  }
  
  validation {
    condition = alltrue([
      var.lambda_memory_size.orchestrator >= 128 && var.lambda_memory_size.orchestrator <= 10240,
      var.lambda_memory_size.cache_manager >= 128 && var.lambda_memory_size.cache_manager <= 10240,
      var.lambda_memory_size.analytics >= 128 && var.lambda_memory_size.analytics <= 10240
    ])
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# EventBridge configuration
variable "enable_eventbridge_rules" {
  description = "Enable EventBridge rules for automated scheduling"
  type        = bool
  default     = true
}

variable "cache_optimization_schedule" {
  description = "EventBridge schedule expression for cache optimization"
  type        = string
  default     = "rate(1 day)"
}

variable "analytics_schedule" {
  description = "EventBridge schedule expression for analytics reporting"
  type        = string
  default     = "rate(7 days)"
}

# CloudWatch configuration
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Source configuration
variable "source_bucket" {
  description = "S3 bucket containing source code (optional, for pre-existing bucket)"
  type        = string
  default     = ""
}

variable "source_key" {
  description = "S3 key for source code archive"
  type        = string
  default     = "source/source.zip"
}

# Security configuration
variable "enable_vpc" {
  description = "Deploy CodeBuild projects in VPC"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for CodeBuild projects (required if enable_vpc is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for CodeBuild projects (required if enable_vpc is true)"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs for CodeBuild projects"
  type        = list(string)
  default     = []
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}