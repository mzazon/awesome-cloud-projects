# Variables for the Quality Gates CodeBuild infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "quality-gates-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "source_location" {
  description = "Git repository URL for the source code"
  type        = string
  default     = "https://github.com/your-org/your-repo.git"
}

variable "build_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 60
  
  validation {
    condition     = var.build_timeout >= 5 && var.build_timeout <= 480
    error_message = "Build timeout must be between 5 and 480 minutes."
  }
}

variable "compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM",
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_XLARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.compute_type)
    error_message = "Compute type must be a valid CodeBuild compute type."
  }
}

variable "build_image" {
  description = "CodeBuild Docker image"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
}

variable "notification_email" {
  description = "Email address for quality gate notifications"
  type        = string
  default     = "developer@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "coverage_threshold" {
  description = "Minimum code coverage percentage"
  type        = number
  default     = 80
  
  validation {
    condition     = var.coverage_threshold >= 0 && var.coverage_threshold <= 100
    error_message = "Coverage threshold must be between 0 and 100."
  }
}

variable "sonar_quality_gate" {
  description = "SonarQube quality gate status threshold"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["OK", "WARN", "ERROR"], var.sonar_quality_gate)
    error_message = "SonarQube quality gate must be one of: OK, WARN, ERROR."
  }
}

variable "security_threshold" {
  description = "Maximum security vulnerability level"
  type        = string
  default     = "HIGH"
  
  validation {
    condition     = contains(["LOW", "MEDIUM", "HIGH", "CRITICAL"], var.security_threshold)
    error_message = "Security threshold must be one of: LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "enable_s3_caching" {
  description = "Enable S3 caching for build dependencies"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for builds"
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Enable SNS notifications for quality gate results"
  type        = bool
  default     = true
}

variable "create_dashboard" {
  description = "Create CloudWatch dashboard for quality metrics"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}