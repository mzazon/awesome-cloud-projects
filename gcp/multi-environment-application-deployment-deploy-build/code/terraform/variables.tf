# variables.tf - Input variables for the multi-environment deployment infrastructure
# This file defines all configurable parameters for the Cloud Deploy and Cloud Build setup

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a, europe-west1-b)."
  }
}

variable "app_name" {
  description = "Name of the application to deploy"
  type        = string
  default     = "sample-webapp"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.app_name))
    error_message = "App name must be 4-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pipeline_name" {
  description = "Name of the Cloud Deploy pipeline"
  type        = string
  default     = "sample-app-pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,58}[a-z0-9]$", var.pipeline_name))
    error_message = "Pipeline name must be 4-60 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_prefix" {
  description = "Prefix for GKE cluster names"
  type        = string
  default     = "deploy-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,18}[a-z0-9]$", var.cluster_prefix))
    error_message = "Cluster prefix must be 4-20 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "gke_autopilot_enabled" {
  description = "Whether to use GKE Autopilot mode for clusters"
  type        = bool
  default     = true
}

variable "gke_release_channel" {
  description = "The GKE release channel for clusters"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.gke_release_channel)
    error_message = "Release channel must be one of: RAPID, REGULAR, STABLE, UNSPECIFIED."
  }
}

variable "environments" {
  description = "Configuration for deployment environments"
  type = map(object({
    require_approval = bool
    deployment_strategy = string
    canary_percentages = optional(list(number))
    verify_deployment = bool
  }))
  default = {
    dev = {
      require_approval = false
      deployment_strategy = "standard"
      verify_deployment = false
    }
    staging = {
      require_approval = true
      deployment_strategy = "standard"
      verify_deployment = true
    }
    prod = {
      require_approval = true
      deployment_strategy = "canary"
      canary_percentages = [25, 50, 100]
      verify_deployment = true
    }
  }
}

variable "cloud_build_timeout" {
  description = "Timeout for Cloud Build operations"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.cloud_build_timeout))
    error_message = "Timeout must be specified in seconds format (e.g., 1200s)."
  }
}

variable "cloud_build_machine_type" {
  description = "Machine type for Cloud Build workers"
  type        = string
  default     = "E2_HIGHCPU_8"
  validation {
    condition = contains([
      "E2_HIGHCPU_8", "E2_HIGHCPU_32", "E2_HIGHMEM_2", "E2_HIGHMEM_4", 
      "E2_HIGHMEM_8", "E2_HIGHMEM_16", "E2_MEDIUM", "E2_STANDARD_2", 
      "E2_STANDARD_4", "E2_STANDARD_8", "E2_STANDARD_16", "E2_STANDARD_32"
    ], var.cloud_build_machine_type)
    error_message = "Machine type must be a valid Cloud Build machine type."
  }
}

variable "storage_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", 
      "us-west2", "us-west3", "us-west4", "europe-north1", "europe-west1", 
      "europe-west2", "europe-west3", "europe-west4", "europe-west6", 
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", 
      "asia-northeast3", "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    application = "multi-env-deploy"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}

variable "create_github_connection" {
  description = "Whether to create a GitHub connection for Cloud Build triggers"
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "GitHub repository for Cloud Build triggers (format: owner/repo)"
  type        = string
  default     = ""
  validation {
    condition     = var.github_repository == "" || can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", var.github_repository))
    error_message = "GitHub repository must be in the format 'owner/repo' or empty string."
  }
}

variable "github_branch_pattern" {
  description = "Branch pattern for GitHub triggers"
  type        = string
  default     = "main"
}