# Variables for AI-Powered App Development with Firebase Studio and Gemini
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "app_name" {
  description = "The name prefix for the AI-powered application resources"
  type        = string
  default     = "ai-task-manager"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name))
    error_message = "App name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "enable_firestore" {
  description = "Whether to enable Firestore database for the application"
  type        = bool
  default     = true
}

variable "firestore_location" {
  description = "The location for Firestore database (multi-region or region)"
  type        = string
  default     = "nam5"  # North America multi-region
  
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "us-central1",
      "us-east1", "us-west2", "europe-west1", "asia-east1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or region."
  }
}

variable "enable_app_hosting" {
  description = "Whether to enable Firebase App Hosting for web application deployment"
  type        = bool
  default     = true
}

variable "enable_cloud_build" {
  description = "Whether to enable Cloud Build for CI/CD pipelines"
  type        = bool
  default     = true
}

variable "enable_secret_manager" {
  description = "Whether to enable Secret Manager for storing API keys"
  type        = bool
  default     = true
}

variable "gemini_api_key" {
  description = "The Gemini API key for AI integration (will be stored in Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_repo_url" {
  description = "The GitHub repository URL for App Hosting integration"
  type        = string
  default     = ""
  
  validation {
    condition = var.github_repo_url == "" || can(regex("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo_url))
    error_message = "GitHub repository URL must be a valid GitHub HTTPS URL or empty."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and Logging"
  type        = bool
  default     = true
}

variable "enable_performance_monitoring" {
  description = "Whether to enable Firebase Performance Monitoring"
  type        = bool
  default     = true
}

variable "enable_analytics" {
  description = "Whether to enable Firebase Analytics (Google Analytics 4)"
  type        = bool
  default     = true
}

variable "authentication_providers" {
  description = "List of authentication providers to enable in Firebase Auth"
  type        = list(string)
  default     = ["google.com", "github.com", "password"]
  
  validation {
    condition = alltrue([
      for provider in var.authentication_providers :
      contains(["google.com", "github.com", "password", "anonymous"], provider)
    ])
    error_message = "Authentication providers must be one of: google.com, github.com, password, anonymous."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins for Firebase services"
  type        = list(string)
  default     = ["https://localhost:3000", "https://localhost:5173"]
}

variable "resource_labels" {
  description = "Labels to apply to all resources for organization and billing"
  type        = map(string)
  default = {
    project     = "ai-powered-app"
    managed-by  = "terraform"
    component   = "firebase-studio"
  }
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 50
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "notification_emails" {
  description = "List of email addresses to receive budget and monitoring alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}