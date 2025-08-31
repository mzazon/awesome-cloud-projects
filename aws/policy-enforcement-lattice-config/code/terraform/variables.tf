# General Configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-west-2"
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
  description = "Project name for resource naming"
  type        = string
  default     = "lattice-compliance"
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for compliance violation notifications"
  type        = string
  default     = "admin@company.com"
}

variable "enable_auto_remediation" {
  description = "Enable automatic remediation of compliance violations"
  type        = bool
  default     = true
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the demo VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# AWS Config Configuration
variable "config_delivery_frequency" {
  description = "Frequency for AWS Config snapshots"
  type        = string
  default     = "TwentyFour_Hours"
  validation {
    condition = contains([
      "One_Hour",
      "Three_Hours", 
      "Six_Hours",
      "Twelve_Hours",
      "TwentyFour_Hours"
    ], var.config_delivery_frequency)
    error_message = "Config delivery frequency must be a valid AWS Config frequency."
  }
}

# Compliance Policy Configuration
variable "require_auth_policy" {
  description = "Require auth policy on VPC Lattice service networks"
  type        = bool
  default     = true
}

variable "service_name_prefix" {
  description = "Required prefix for VPC Lattice service network names"
  type        = string
  default     = "secure-"
}

variable "require_service_auth" {
  description = "Require authentication on VPC Lattice services"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 120
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Demo Resources
variable "create_demo_resources" {
  description = "Create demo VPC Lattice resources for testing"
  type        = bool
  default     = true
}

variable "demo_service_name" {
  description = "Name for demo VPC Lattice service (will be non-compliant for testing)"
  type        = string
  default     = "test-service"
}