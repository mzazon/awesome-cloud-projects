# Variables for multi-branch CI/CD pipeline infrastructure
# This file defines all configurable parameters for the multi-branch pipeline deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner of the resources for tagging purposes"
  type        = string
  default     = "devops-team"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "multi-branch-app"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name can only contain letters, numbers, and hyphens."
  }
}

variable "repository_name" {
  description = "Name of the CodeCommit repository"
  type        = string
  default     = null
  
  validation {
    condition = var.repository_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.repository_name))
    error_message = "Repository name can only contain letters, numbers, dots, underscores, and hyphens."
  }
}

variable "repository_description" {
  description = "Description of the CodeCommit repository"
  type        = string
  default     = "Multi-branch CI/CD demo application repository"
}

variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild projects"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  
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
  description = "Docker image for CodeBuild environment"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for CodeBuild projects"
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch log retention period."
  }
}

variable "enable_pipeline_notifications" {
  description = "Enable SNS notifications for pipeline events"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for pipeline notifications"
  type        = string
  default     = null
  
  validation {
    condition = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "feature_branch_prefix" {
  description = "Prefix for feature branches that should trigger pipeline creation"
  type        = string
  default     = "feature/"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_/]+$", var.feature_branch_prefix))
    error_message = "Feature branch prefix can only contain letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "permanent_branches" {
  description = "List of permanent branches that should have persistent pipelines"
  type        = list(string)
  default     = ["main", "develop"]
  
  validation {
    condition = length(var.permanent_branches) > 0
    error_message = "At least one permanent branch must be specified."
  }
}

variable "buildspec_file" {
  description = "Path to the buildspec file in the repository"
  type        = string
  default     = "buildspec.yml"
}

variable "enable_code_coverage" {
  description = "Enable code coverage reporting in CodeBuild"
  type        = bool
  default     = false
}

variable "enable_security_scanning" {
  description = "Enable security scanning in CodeBuild"
  type        = bool
  default     = false
}

variable "artifact_bucket_name" {
  description = "Name of the S3 bucket for pipeline artifacts (leave null for auto-generated)"
  type        = string
  default     = null
  
  validation {
    condition = var.artifact_bucket_name == null || can(regex("^[a-z0-9.-]+$", var.artifact_bucket_name))
    error_message = "Artifact bucket name must contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "enable_artifact_encryption" {
  description = "Enable encryption for pipeline artifacts"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting pipeline artifacts (leave null for default)"
  type        = string
  default     = null
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for artifact bucket"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "Backup region for cross-region replication"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.backup_region))
    error_message = "Backup region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "enable_vpc_configuration" {
  description = "Enable VPC configuration for CodeBuild projects"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for CodeBuild projects (required if enable_vpc_configuration is true)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for CodeBuild projects (required if enable_vpc_configuration is true)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for CodeBuild projects"
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}