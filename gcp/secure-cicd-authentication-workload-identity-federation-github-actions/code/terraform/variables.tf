# Variable definitions for Workload Identity Federation with GitHub Actions
# This file defines all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where regional resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone where zonal resources will be created"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "github_repo_owner" {
  description = "The GitHub repository owner (username or organization)"
  type        = string
  validation {
    condition     = length(var.github_repo_owner) > 0
    error_message = "GitHub repository owner cannot be empty."
  }
}

variable "github_repo_name" {
  description = "The GitHub repository name"
  type        = string
  validation {
    condition     = length(var.github_repo_name) > 0
    error_message = "GitHub repository name cannot be empty."
  }
}

variable "resource_prefix" {
  description = "Prefix to be used for all resource names"
  type        = string
  default     = "wif-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "workload_identity_pool_id" {
  description = "ID for the Workload Identity Pool (if not provided, will be generated)"
  type        = string
  default     = ""
  validation {
    condition     = var.workload_identity_pool_id == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workload_identity_pool_id))
    error_message = "Workload Identity Pool ID must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "workload_identity_provider_id" {
  description = "ID for the GitHub OIDC provider (if not provided, will be generated)"
  type        = string
  default     = ""
  validation {
    condition     = var.workload_identity_provider_id == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workload_identity_provider_id))
    error_message = "Workload Identity Provider ID must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "service_account_id" {
  description = "ID for the GitHub Actions service account (if not provided, will be generated)"
  type        = string
  default     = ""
  validation {
    condition     = var.service_account_id == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_id))
    error_message = "Service Account ID must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "artifact_repository_name" {
  description = "Name for the Artifact Registry repository (if not provided, will be generated)"
  type        = string
  default     = ""
  validation {
    condition     = var.artifact_repository_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.artifact_repository_name))
    error_message = "Artifact Repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service (if not provided, will be generated)"
  type        = string
  default     = ""
  validation {
    condition     = var.cloud_run_service_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cloud_run_service_name))
    error_message = "Cloud Run service name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs (disable if APIs are already enabled)"
  type        = bool
  default     = true
}

variable "additional_github_repos" {
  description = "Additional GitHub repositories that should have access to the service account (format: owner/repo)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for repo in var.additional_github_repos : can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", repo))
    ])
    error_message = "Additional GitHub repositories must be in the format 'owner/repo'."
  }
}

variable "service_account_display_name" {
  description = "Display name for the GitHub Actions service account"
  type        = string
  default     = "GitHub Actions Service Account"
}

variable "workload_identity_pool_display_name" {
  description = "Display name for the Workload Identity Pool"
  type        = string
  default     = "GitHub Actions Pool"
}

variable "workload_identity_provider_display_name" {
  description = "Display name for the GitHub OIDC provider"
  type        = string
  default     = "GitHub OIDC Provider"
}

variable "artifact_repository_description" {
  description = "Description for the Artifact Registry repository"
  type        = string
  default     = "Repository for CI/CD container images"
}

variable "custom_iam_roles" {
  description = "Additional IAM roles to grant to the service account beyond the default CI/CD roles"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for role in var.custom_iam_roles : can(regex("^roles/[a-zA-Z0-9._-]+$", role))
    ])
    error_message = "Custom IAM roles must be in the format 'roles/roleName'."
  }
}

variable "tags" {
  description = "Resource tags to apply to all resources"
  type        = map(string)
  default     = {}
}