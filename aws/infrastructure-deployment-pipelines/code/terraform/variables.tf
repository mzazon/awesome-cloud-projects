# AWS Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
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

# Project Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cdk-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Repository Configuration
variable "repository_name" {
  description = "Name of the CodeCommit repository"
  type        = string
  default     = ""
}

variable "repository_description" {
  description = "Description of the CodeCommit repository"
  type        = string
  default     = "Infrastructure deployment pipeline repository"
}

variable "branch_name" {
  description = "Branch name to trigger the pipeline"
  type        = string
  default     = "main"
}

# Pipeline Configuration
variable "pipeline_name" {
  description = "Name of the CodePipeline"
  type        = string
  default     = "InfrastructurePipeline"
}

variable "enable_manual_approval" {
  description = "Enable manual approval for production deployments"
  type        = bool
  default     = true
}

variable "approval_timeout_minutes" {
  description = "Timeout for manual approval in minutes"
  type        = number
  default     = 60
}

# CodeBuild Configuration
variable "codebuild_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM", 
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "Invalid CodeBuild compute type."
  }
}

variable "codebuild_image" {
  description = "CodeBuild Docker image"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "nodejs_version" {
  description = "Node.js version for CDK builds"
  type        = string
  default     = "18"
}

# Notification Configuration
variable "enable_notifications" {
  description = "Enable SNS notifications for pipeline events"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for pipeline notifications"
  type        = string
  default     = ""
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 artifacts and SNS topics"
  type        = bool
  default     = true
}

variable "artifact_retention_days" {
  description = "Number of days to retain build artifacts"
  type        = number
  default     = 30
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for CodeBuild"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

# Cross-Account Deployment Configuration
variable "target_accounts" {
  description = "Map of target accounts for cross-account deployments"
  type = map(object({
    account_id = string
    role_arn   = string
  }))
  default = {}
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}