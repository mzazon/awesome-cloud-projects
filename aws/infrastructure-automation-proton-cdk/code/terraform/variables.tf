# General Configuration
variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "proton-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

# Proton Configuration
variable "proton_service_role_name" {
  description = "Name for the Proton service role"
  type        = string
  default     = "ProtonServiceRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.proton_service_role_name))
    error_message = "Role name must contain only valid IAM role name characters."
  }
}

variable "environment_template_name" {
  description = "Name for the Proton environment template"
  type        = string
  default     = "web-app-env"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment_template_name))
    error_message = "Template name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_template_name" {
  description = "Name for the Proton service template"
  type        = string
  default     = "web-app-svc"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_template_name))
    error_message = "Template name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Environment Template Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC in environment template"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable Container Insights for ECS cluster"
  type        = bool
  default     = true
}

# S3 Configuration for Templates
variable "template_bucket_name" {
  description = "Name for the S3 bucket to store Proton templates (will be suffixed with random string)"
  type        = string
  default     = "proton-templates"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.template_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "template_bucket_versioning" {
  description = "Enable versioning for the template bucket"
  type        = bool
  default     = true
}

# IAM Configuration
variable "create_proton_service_role" {
  description = "Whether to create the Proton service role"
  type        = bool
  default     = true
}

variable "proton_managed_policies" {
  description = "List of managed policies to attach to the Proton service role"
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/AWSProtonFullAccess",
    "arn:aws:iam::aws:policy/AWSCloudFormationFullAccess"
  ]
}

# Template Configuration
variable "template_description" {
  description = "Description for the Proton templates"
  type        = string
  default     = "Standardized infrastructure templates for web applications"
}

variable "template_display_name" {
  description = "Display name for the environment template"
  type        = string
  default     = "Web Application Environment"
}

variable "auto_publish_template" {
  description = "Automatically publish template versions after creation"
  type        = bool
  default     = true
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}