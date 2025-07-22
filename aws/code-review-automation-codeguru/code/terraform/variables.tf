# Variables for CodeGuru Automation Infrastructure
# This file defines all configurable parameters for the CodeGuru automation setup

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
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "codeguru-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "repository_name" {
  description = "Name for the CodeCommit repository"
  type        = string
  default     = ""
}

variable "repository_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "Demo repository for CodeGuru automation and code review"
}

variable "profiler_group_name" {
  description = "Name for the CodeGuru Profiler group"
  type        = string
  default     = ""
}

variable "iam_role_name" {
  description = "Name for the IAM role used by CodeGuru services"
  type        = string
  default     = ""
}

variable "enable_codeguru_reviewer" {
  description = "Enable CodeGuru Reviewer for the repository"
  type        = bool
  default     = true
}

variable "enable_codeguru_profiler" {
  description = "Enable CodeGuru Profiler group creation"
  type        = bool
  default     = true
}

variable "enable_code_quality_gates" {
  description = "Enable automated code quality gate enforcement"
  type        = bool
  default     = true
}

variable "max_severity_threshold" {
  description = "Maximum allowed severity level for quality gates (INFO, LOW, MEDIUM, HIGH, CRITICAL)"
  type        = string
  default     = "MEDIUM"
  
  validation {
    condition     = contains(["INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"], var.max_severity_threshold)
    error_message = "Severity threshold must be one of: INFO, LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "profiler_compute_platform" {
  description = "Compute platform for CodeGuru Profiler (Default, AWSLambda)"
  type        = string
  default     = "Default"
  
  validation {
    condition     = contains(["Default", "AWSLambda"], var.profiler_compute_platform)
    error_message = "Compute platform must be either 'Default' or 'AWSLambda'."
  }
}

variable "create_sample_code" {
  description = "Whether to create sample code files in the repository"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for CodeGuru notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

variable "enable_eventbridge_integration" {
  description = "Enable EventBridge integration for CodeGuru events"
  type        = bool
  default     = false
}

variable "custom_detector_s3_bucket" {
  description = "S3 bucket name for custom CodeGuru detector rules (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}