# Variables for Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Mobile Application Configuration
variable "android_app_display_name" {
  description = "Display name for the Android application in Firebase"
  type        = string
  default     = "Mobile CI/CD Demo App"
}

variable "android_package_name" {
  description = "Android application package name"
  type        = string
  default     = "com.example.mobilecicd"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)*$", var.android_package_name))
    error_message = "Package name must follow Android package naming conventions."
  }
}

variable "ios_app_display_name" {
  description = "Display name for the iOS application in Firebase"
  type        = string
  default     = "Mobile CI/CD Demo App iOS"
}

variable "ios_bundle_id" {
  description = "iOS application bundle identifier"
  type        = string
  default     = "com.example.mobilecicd"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*([.][a-zA-Z][a-zA-Z0-9_]*)*$", var.ios_bundle_id))
    error_message = "Bundle ID must follow iOS bundle identifier conventions."
  }
}

# Source Repository Configuration
variable "repository_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "mobile-app-source"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.repository_name))
    error_message = "Repository name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Build Configuration
variable "build_trigger_name" {
  description = "Name for the Cloud Build trigger"
  type        = string
  default     = "mobile-cicd-trigger"
}

variable "feature_branch_trigger_name" {
  description = "Name for the feature branch Cloud Build trigger"
  type        = string
  default     = "feature-branch-trigger"
}

variable "build_config_filename" {
  description = "Filename for the Cloud Build configuration"
  type        = string
  default     = "cloudbuild.yaml"
}

variable "main_branch_pattern" {
  description = "Regex pattern for main branch builds"
  type        = string
  default     = "^main$"
}

variable "feature_branch_pattern" {
  description = "Regex pattern for feature branch builds"
  type        = string
  default     = "^feature/.*"
}

# Firebase Test Lab Configuration
variable "test_devices" {
  description = "List of device configurations for Firebase Test Lab"
  type = list(object({
    model       = string
    version     = string
    locale      = string
    orientation = string
  }))
  default = [
    {
      model       = "Pixel2"
      version     = "28"
      locale      = "en"
      orientation = "portrait"
    },
    {
      model       = "Pixel3"
      version     = "29"
      locale      = "en"
      orientation = "portrait"
    },
    {
      model       = "Pixel4"
      version     = "30"
      locale      = "en"
      orientation = "portrait"
    }
  ]
}

# App Distribution Configuration
variable "tester_groups" {
  description = "List of tester groups for Firebase App Distribution"
  type        = list(string)
  default     = ["qa-team", "stakeholders", "beta-users"]
}

variable "default_testers" {
  description = "List of default tester email addresses"
  type        = list(string)
  default     = []
}

# Cloud Build Service Account Configuration
variable "build_service_account_name" {
  description = "Name for the Cloud Build service account"
  type        = string
  default     = "mobile-cicd-build-sa"
}

# Storage Configuration
variable "artifact_bucket_name" {
  description = "Name for the build artifacts storage bucket (will be auto-generated if empty)"
  type        = string
  default     = ""
}

variable "artifact_bucket_location" {
  description = "Location for the build artifacts storage bucket"
  type        = string
  default     = "US"
}

# Notification Configuration
variable "enable_build_notifications" {
  description = "Enable Pub/Sub notifications for build status"
  type        = bool
  default     = true
}

variable "notification_topic_name" {
  description = "Name for the Pub/Sub topic for build notifications"
  type        = string
  default     = "mobile-build-notifications"
}

# Security Configuration
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container images"
  type        = bool
  default     = false
}

variable "enable_vulnerability_scanning" {
  description = "Enable container vulnerability scanning"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "mobile-cicd"
    managed-by  = "terraform"
  }
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}