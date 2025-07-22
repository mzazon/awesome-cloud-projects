# Variables for Firebase Studio and Gemini Code Assist Development Environment
# This file defines all configurable variables for the Terraform configuration

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1", "europe-west1", "europe-west2", "asia-east1", "asia-northeast1"], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "firebase-studio"
  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 1-20 characters, lowercase letters, numbers, and hyphens only."
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

# Firebase Configuration
variable "firebase_project_display_name" {
  description = "Display name for the Firebase project"
  type        = string
  default     = "AI Development Environment"
}

variable "firebase_location" {
  description = "Location for Firebase resources (must be compatible with Firestore)"
  type        = string
  default     = "us-central"
  validation {
    condition     = contains(["us-central", "us-east1", "us-west1", "europe-west1", "europe-west2", "asia-east1", "asia-northeast1"], var.firebase_location)
    error_message = "Firebase location must be a valid Firebase location."
  }
}

# Source Repository Configuration
variable "repository_name" {
  description = "Name for the Cloud Source Repository"
  type        = string
  default     = "ai-app-repo"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.repository_name))
    error_message = "Repository name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Artifact Registry Configuration
variable "artifact_repository_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = "ai-app-registry"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.artifact_repository_name))
    error_message = "Artifact repository name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "artifact_repository_format" {
  description = "Format of the Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM"], var.artifact_repository_format)
    error_message = "Artifact repository format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM."
  }
}

# Cloud Build Configuration
variable "build_trigger_name" {
  description = "Name for the Cloud Build trigger"
  type        = string
  default     = "ai-app-build-trigger"
}

variable "build_trigger_branch" {
  description = "Git branch that triggers the build"
  type        = string
  default     = "main"
}

variable "build_config_filename" {
  description = "Name of the build configuration file"
  type        = string
  default     = "cloudbuild.yaml"
}

# Cloud Run Configuration
variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "ai-app"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.cloud_run_service_name))
    error_message = "Cloud Run service name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1000m"
  validation {
    condition     = contains(["1000m", "2000m", "4000m", "8000m"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 1000m, 2000m, 4000m, 8000m."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition     = contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.cloud_run_memory)
    error_message = "Memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

# AI Platform Configuration
variable "enable_ai_platform" {
  description = "Enable AI Platform services for Gemini Code Assist"
  type        = bool
  default     = true
}

variable "gemini_model_name" {
  description = "Gemini model name for code assistance"
  type        = string
  default     = "gemini-pro"
  validation {
    condition     = contains(["gemini-pro", "gemini-pro-vision", "gemini-1.5-pro"], var.gemini_model_name)
    error_message = "Gemini model must be one of: gemini-pro, gemini-pro-vision, gemini-1.5-pro."
  }
}

# Security Configuration
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = true
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and Logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Networking Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for the VPC"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "firebase-studio-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "firebase-studio-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "firebase-studio"
    managed-by  = "terraform"
  }
}

# Cost Management
variable "enable_cost_alerts" {
  description = "Enable billing alerts for cost management"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}