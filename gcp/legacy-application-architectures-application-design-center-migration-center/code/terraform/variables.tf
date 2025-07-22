# Variables for legacy application modernization infrastructure

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID for deploying resources"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The default region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "The default zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

# Application Configuration
variable "app_name" {
  description = "Base name for the modernized application resources"
  type        = string
  default     = "legacy-modernization"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.app_name))
    error_message = "App name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 63 characters or less."
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

# Migration Center Configuration
variable "migration_center_enabled" {
  description = "Enable Migration Center for legacy application discovery"
  type        = bool
  default     = true
}

variable "discovery_source_name" {
  description = "Name for the Migration Center discovery source"
  type        = string
  default     = "legacy-discovery"
}

variable "discovery_client_name" {
  description = "Name for the Migration Center discovery client"
  type        = string
  default     = "legacy-client"
}

# Application Design Center Configuration
variable "adc_enabled" {
  description = "Enable Application Design Center for application modernization"
  type        = bool
  default     = true
}

variable "adc_space_name" {
  description = "Name for the Application Design Center space"
  type        = string
  default     = "modernization-space"
}

# Cloud Build Configuration
variable "build_enabled" {
  description = "Enable Cloud Build for CI/CD pipeline"
  type        = bool
  default     = true
}

variable "repository_name" {
  description = "Name for the Cloud Source Repository"
  type        = string
  default     = "modernized-apps"
}

variable "trigger_branch" {
  description = "Git branch to trigger builds"
  type        = string
  default     = "main"
}

# Cloud Deploy Configuration
variable "deploy_enabled" {
  description = "Enable Cloud Deploy for multi-environment deployment"
  type        = bool
  default     = true
}

variable "delivery_pipeline_name" {
  description = "Name for the Cloud Deploy delivery pipeline"
  type        = string
  default     = "modernized-app-pipeline"
}

# Cloud Run Configuration
variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "modernized-service"
}

variable "service_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["1", "2", "4", "8"], var.service_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "service_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "2Gi"
  validation {
    condition     = can(regex("^[0-9]+[GM]i$", var.service_memory))
    error_message = "Memory must be in format like '2Gi' or '512Mi'."
  }
}

variable "service_max_instances" {
  description = "Maximum number of instances for Cloud Run service"
  type        = number
  default     = 10
  validation {
    condition     = var.service_max_instances >= 1 && var.service_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "service_concurrency" {
  description = "Maximum concurrent requests per instance"
  type        = number
  default     = 80
  validation {
    condition     = var.service_concurrency >= 1 && var.service_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Run service"
  type        = bool
  default     = true
}

# Container Registry Configuration
variable "container_registry_enabled" {
  description = "Enable Container Registry for storing application images"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "monitoring_enabled" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "dashboard_enabled" {
  description = "Create monitoring dashboard for the application"
  type        = bool
  default     = true
}

variable "alerting_enabled" {
  description = "Enable alerting policies for the application"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting (percentage)"
  type        = number
  default     = 5.0
  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100."
  }
}

# Security Configuration
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = false
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

# IAM Configuration
variable "custom_service_account" {
  description = "Custom service account email for Cloud Run (optional)"
  type        = string
  default     = ""
}

# Networking Configuration
variable "vpc_connector_enabled" {
  description = "Enable VPC connector for Cloud Run (for private resources)"
  type        = bool
  default     = false
}

variable "vpc_network_name" {
  description = "VPC network name for VPC connector (if enabled)"
  type        = string
  default     = "default"
}

variable "vpc_subnet_name" {
  description = "VPC subnet name for VPC connector (if enabled)"
  type        = string
  default     = "default"
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "legacy-modernization"
    managed-by  = "terraform"
  }
}

# Cost Management
variable "budget_enabled" {
  description = "Enable budget alerts for cost management"
  type        = bool
  default     = false
}

variable "budget_amount" {
  description = "Budget amount in USD for cost alerts"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}