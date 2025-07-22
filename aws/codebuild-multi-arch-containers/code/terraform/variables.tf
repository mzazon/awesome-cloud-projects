# Variables for multi-architecture container images with CodeBuild
# This file defines all customizable input variables

# AWS Configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "multi-arch-build"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ECR Repository Configuration
variable "ecr_repository_name" {
  description = "Name of the ECR repository for storing multi-architecture images"
  type        = string
  default     = "sample-app"
  
  validation {
    condition = can(regex("^[a-z0-9-/_]+$", var.ecr_repository_name))
    error_message = "ECR repository name must contain only lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

# CodeBuild Configuration
variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild project"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM", 
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_XLARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "CodeBuild compute type must be a valid BUILD_GENERAL1_* type."
  }
}

variable "codebuild_image" {
  description = "Docker image for CodeBuild project"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "codebuild_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 60
  
  validation {
    condition = var.codebuild_timeout >= 5 && var.codebuild_timeout <= 480
    error_message = "CodeBuild timeout must be between 5 and 480 minutes."
  }
}

variable "codebuild_privileged_mode" {
  description = "Enable privileged mode for Docker-in-Docker functionality"
  type        = bool
  default     = true
}

# Source Configuration
variable "source_location" {
  description = "S3 location for source code (optional - will be created if not provided)"
  type        = string
  default     = ""
}

variable "source_type" {
  description = "Source type for CodeBuild project"
  type        = string
  default     = "S3"
  
  validation {
    condition = contains(["S3", "GITHUB", "CODECOMMIT", "CODEPIPELINE"], var.source_type)
    error_message = "Source type must be one of: S3, GITHUB, CODECOMMIT, CODEPIPELINE."
  }
}

# Build Specification
variable "buildspec_file" {
  description = "Path to buildspec file (relative to source root)"
  type        = string
  default     = "buildspec.yml"
}

# Target Platforms
variable "target_platforms" {
  description = "List of target platforms for multi-architecture builds"
  type        = list(string)
  default     = ["linux/amd64", "linux/arm64"]
  
  validation {
    condition = length(var.target_platforms) > 0
    error_message = "At least one target platform must be specified."
  }
}

# Cache Configuration
variable "cache_type" {
  description = "Cache type for CodeBuild project"
  type        = string
  default     = "LOCAL"
  
  validation {
    condition = contains(["NO_CACHE", "LOCAL", "S3"], var.cache_type)
    error_message = "Cache type must be one of: NO_CACHE, LOCAL, S3."
  }
}

variable "cache_modes" {
  description = "Cache modes for LOCAL cache type"
  type        = list(string)
  default     = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  
  validation {
    condition = alltrue([
      for mode in var.cache_modes : contains([
        "LOCAL_DOCKER_LAYER_CACHE",
        "LOCAL_SOURCE_CACHE",
        "LOCAL_CUSTOM_CACHE"
      ], mode)
    ])
    error_message = "Cache modes must be valid LOCAL_* cache modes."
  }
}

# Resource Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Security Configuration
variable "enable_vpc_config" {
  description = "Enable VPC configuration for CodeBuild project"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for CodeBuild project (required if enable_vpc_config is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for CodeBuild project (required if enable_vpc_config is true)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for CodeBuild project (required if enable_vpc_config is true)"
  type        = list(string)
  default     = []
}

# Lifecycle Configuration
variable "ecr_lifecycle_policy" {
  description = "Enable lifecycle policy for ECR repository"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to retain in ECR repository"
  type        = number
  default     = 10
  
  validation {
    condition = var.max_image_count > 0
    error_message = "Maximum image count must be greater than 0."
  }
}