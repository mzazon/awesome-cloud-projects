# Core project and regional configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters long."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources that require a specific zone"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "code-quality"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# Cloud Source Repository configuration
variable "repository_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "secure-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.repository_name))
    error_message = "Repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# GKE cluster configuration
variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "quality-enforcement-cluster"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "node_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.node_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

# Cloud Build configuration
variable "trigger_branch_pattern" {
  description = "Branch pattern for Cloud Build trigger"
  type        = string
  default     = "^main$"
}

variable "build_timeout" {
  description = "Timeout for Cloud Build in seconds"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.build_timeout))
    error_message = "Build timeout must be in seconds format (e.g., 1200s)."
  }
}

# Binary Authorization configuration
variable "binauthz_policy_enforcement_mode" {
  description = "Binary Authorization policy enforcement mode"
  type        = string
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  validation {
    condition = contains([
      "ALWAYS_ALLOW", "ALWAYS_DENY", "ENFORCED_BLOCK_AND_AUDIT_LOG", "DRYRUN_AUDIT_LOG_ONLY"
    ], var.binauthz_policy_enforcement_mode)
    error_message = "Enforcement mode must be one of: ALWAYS_ALLOW, ALWAYS_DENY, ENFORCED_BLOCK_AND_AUDIT_LOG, DRYRUN_AUDIT_LOG_ONLY."
  }
}

# Security Command Center configuration
variable "scc_source_display_name" {
  description = "Display name for the Security Command Center source"
  type        = string
  default     = "Code Quality Enforcement Pipeline"
}

variable "scc_source_description" {
  description = "Description for the Security Command Center source"
  type        = string
  default     = "Security findings from automated code quality pipeline"
}

# Container image configuration
variable "container_image_name" {
  description = "Name of the container image"
  type        = string
  default     = "secure-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.container_image_name))
    error_message = "Container image name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# KMS configuration
variable "kms_key_ring_name" {
  description = "Name of the KMS key ring for Binary Authorization"
  type        = string
  default     = "binauthz-ring"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_key_ring_name))
    error_message = "KMS key ring name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "kms_key_name" {
  description = "Name of the KMS key for attestation signing"
  type        = string
  default     = "attestor-key"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_key_name))
    error_message = "KMS key name must contain only letters, numbers, underscores, and hyphens."
  }
}

# Enable/disable features
variable "enable_shielded_nodes" {
  description = "Enable shielded nodes for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable workload identity for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_container_scanning" {
  description = "Enable container image vulnerability scanning"
  type        = bool
  default     = true
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "code-quality-enforcement"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z][a-z0-9_-]*$", key)) && can(regex("^[a-z0-9_-]*$", value))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}