# Variables for Infrastructure Testing Strategy

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming and tagging)"
  type        = string
  default     = "iac-testing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
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

variable "repository_name" {
  description = "Name of the CodeCommit repository"
  type        = string
  default     = null
}

variable "bucket_name" {
  description = "Name of the S3 bucket for artifacts (will be auto-generated if not provided)"
  type        = string
  default     = null
}

variable "codebuild_compute_type" {
  description = "CodeBuild compute type for the testing environment"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM", 
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "CodeBuild compute type must be a valid value."
  }
}

variable "codebuild_image" {
  description = "CodeBuild container image for the testing environment"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

variable "enable_pipeline" {
  description = "Whether to create the CodePipeline (set to false for CodeBuild-only setup)"
  type        = bool
  default     = true
}

variable "pipeline_branch" {
  description = "Git branch to trigger the pipeline"
  type        = string
  default     = "main"
}

variable "notification_email" {
  description = "Email address for build notifications (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "testing_tools" {
  description = "List of testing tools to install and configure"
  type        = list(string)
  default = [
    "cfn-lint",
    "cfn-nag", 
    "checkov",
    "pytest",
    "moto"
  ]
}

variable "custom_buildspec_path" {
  description = "Custom path to buildspec.yml file (optional)"
  type        = string
  default     = "buildspec.yml"
}

variable "retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_days > 0 && var.retention_days <= 3653
    error_message = "Retention days must be between 1 and 3653 days."
  }
}

variable "artifact_encryption" {
  description = "Whether to enable encryption for pipeline artifacts"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}