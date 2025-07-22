# Variables for ECR Container Registry Replication Strategies
# Defines customizable parameters for the infrastructure deployment

variable "source_region" {
  description = "AWS region for source ECR registries"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.source_region))
    error_message = "Source region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "destination_region" {
  description = "AWS region for destination ECR registries"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.destination_region))
    error_message = "Destination region must be a valid AWS region format (e.g., us-west-2)."
  }
}

variable "secondary_region" {
  description = "AWS region for secondary ECR registries"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

variable "repository_prefix" {
  description = "Prefix for ECR repository names"
  type        = string
  default     = "enterprise-apps"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.repository_prefix))
    error_message = "Repository prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource tagging"
  type        = string
  default     = "ecr-replication-strategy"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_image_scanning" {
  description = "Enable image scanning for ECR repositories"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for monitoring alarms"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "production_image_retention_count" {
  description = "Number of production images to retain"
  type        = number
  default     = 10
  
  validation {
    condition     = var.production_image_retention_count >= 1 && var.production_image_retention_count <= 100
    error_message = "Production image retention count must be between 1 and 100."
  }
}

variable "testing_image_retention_count" {
  description = "Number of testing images to retain"
  type        = number
  default     = 5
  
  validation {
    condition     = var.testing_image_retention_count >= 1 && var.testing_image_retention_count <= 50
    error_message = "Testing image retention count must be between 1 and 50."
  }
}

variable "untagged_image_retention_days" {
  description = "Days to retain untagged images"
  type        = number
  default     = 1
  
  validation {
    condition     = var.untagged_image_retention_days >= 1 && var.untagged_image_retention_days <= 30
    error_message = "Untagged image retention days must be between 1 and 30."
  }
}

variable "testing_image_retention_days" {
  description = "Days to retain testing images"
  type        = number
  default     = 7
  
  validation {
    condition     = var.testing_image_retention_days >= 1 && var.testing_image_retention_days <= 90
    error_message = "Testing image retention days must be between 1 and 90."
  }
}

variable "replication_failure_threshold" {
  description = "Threshold for replication failure rate alarm (0.0 to 1.0)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.replication_failure_threshold >= 0.0 && var.replication_failure_threshold <= 1.0
    error_message = "Replication failure threshold must be between 0.0 and 1.0."
  }
}

variable "create_iam_roles" {
  description = "Create IAM roles for ECR access (set to false if roles already exist)"
  type        = bool
  default     = true
}

variable "existing_production_role_arn" {
  description = "ARN of existing production role (used when create_iam_roles is false)"
  type        = string
  default     = ""
}

variable "existing_ci_pipeline_role_arn" {
  description = "ARN of existing CI/CD pipeline role (used when create_iam_roles is false)"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ECR-Replication-Strategy"
    Environment = "production"
    ManagedBy   = "terraform"
    Recipe      = "container-registry-replication-strategies-ecr"
  }
}