# Common variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "security-scanning"
}

# ECR variables
variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "secure-app"
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

# Enhanced scanning variables
variable "enable_enhanced_scanning" {
  description = "Enable enhanced scanning with Amazon Inspector"
  type        = bool
  default     = true
}

variable "scan_frequency" {
  description = "Scan frequency for enhanced scanning"
  type        = string
  default     = "CONTINUOUS_SCAN"
  validation {
    condition     = contains(["SCAN_ON_PUSH", "CONTINUOUS_SCAN"], var.scan_frequency)
    error_message = "Scan frequency must be either SCAN_ON_PUSH or CONTINUOUS_SCAN."
  }
}

# CodeBuild variables
variable "codebuild_image" {
  description = "CodeBuild container image"
  type        = string
  default     = "aws/codebuild/standard:5.0"
}

variable "codebuild_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
}

variable "github_repo_url" {
  description = "GitHub repository URL for CodeBuild source"
  type        = string
  default     = "https://github.com/your-org/your-repo.git"
}

# Third-party scanner variables
variable "enable_snyk_scanning" {
  description = "Enable Snyk vulnerability scanning"
  type        = bool
  default     = true
}

variable "enable_prisma_scanning" {
  description = "Enable Prisma Cloud scanning"
  type        = bool
  default     = false
}

variable "snyk_token_secret_name" {
  description = "AWS Secrets Manager secret name for Snyk token"
  type        = string
  default     = "snyk-token"
}

variable "prisma_credentials_secret_name" {
  description = "AWS Secrets Manager secret name for Prisma Cloud credentials"
  type        = string
  default     = "prisma-credentials"
}

# Security thresholds
variable "critical_vulnerability_threshold" {
  description = "Threshold for critical vulnerabilities before blocking deployment"
  type        = number
  default     = 0
}

variable "high_vulnerability_threshold" {
  description = "Threshold for high vulnerabilities before review required"
  type        = number
  default     = 5
}

# Notification variables
variable "notification_email" {
  description = "Email address for security notifications"
  type        = string
  default     = "security-team@company.com"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
}

# CloudWatch variables
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
}

# Config variables
variable "enable_config_rules" {
  description = "Enable AWS Config rules for compliance monitoring"
  type        = bool
  default     = true
}

# Security Hub variables
variable "enable_security_hub" {
  description = "Enable AWS Security Hub integration"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}